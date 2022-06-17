Mix.install([
  :membrane_core,
  {:membrane_matroska_plugin, path: __DIR__ |> Path.join("..") |> Path.expand()},
  :membrane_hackney_plugin,
  :membrane_h264_ffmpeg_plugin,
  :membrane_mp4_plugin,
  :membrane_opus_plugin,
])

defmodule Example do
  use Membrane.Pipeline

  alias Membrane.RawAudio

  @samples_url "https://raw.githubusercontent.com/membraneframework/static/gh-pages/samples/"
  @video_url @samples_url <> "ffmpeg-testsrc.h264"
  @audio_url @samples_url <> "beep-s16le-48kHz-stereo.raw"
  @output_file Path.expand("example_h264.mkv")

  @impl true
  def handle_init(_options) do
    children = [
      muxer: Membrane.Matroska.Muxer,
      video_source: %Membrane.Hackney.Source{
        location: @video_url,
        hackney_opts: [follow_redirect: true]
      },
      video_parser: %Membrane.H264.FFmpeg.Parser{
        framerate: {30, 1},
        alignment: :au,
        attach_nalus?: true
      },
      video_payloader: %Membrane.MP4.Payloader.H264{parameters_in_band?: true},
      audio_source: %Membrane.Hackney.Source{
        location: @audio_url,
        hackney_opts: [follow_redirect: true]
      },
      audio_encoder: %Membrane.Opus.Encoder{
        application: :audio,
        input_caps: %RawAudio{
          channels: 2,
          sample_format: :s16le,
          sample_rate: 48_000
        }
      },
      audio_parser: %Membrane.Opus.Parser{delimitation: :undelimit},
      file_sink: %Membrane.File.Sink{location: @output_file}
    ]

    links = [
      link(:video_source)
      |> to(:video_parser)
      |> to(:video_payloader)
      |> to(:muxer),
      link(:audio_source)
      |> to(:audio_encoder)
      |> to(:audio_parser)
      |> to(:muxer),
      link(:muxer) |> to(:file_sink)
    ]

    {{:ok, spec: %ParentSpec{children: children, links: links}, playback: :playing}, %{}}
  end


  # Next two functions are only a logic for terminating a pipeline when it's done, you don't need to worry
  @impl true
  def handle_element_end_of_stream({:file_sink, _}, _ctx, state) do
    Membrane.Pipeline.terminate(self())
    {:ok, state}
  end

  def handle_element_end_of_stream(_element, _ctx, state) do
    {:ok, state}
  end
end

{:ok, pipeline} = Example.start_link()
monitor_ref = Process.monitor(pipeline)

receive do
  {:DOWN, ^monitor_ref, :process, _pid, _reason} ->
    :ok
end
