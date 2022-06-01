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

  @samples_url "https://raw.githubusercontent.com/membraneframework/static/matroska/samples/"
  @video_url @samples_url <> "ffmpeg-testsrc.h264"
  # @audio_url @samples_url <> "beep.opus"
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
      audio_parser: %Membrane.Opus.Parser{delimitation: :delimit},
      file_sink: %Membrane.File.Sink{location: @output_file}
    ]

    links = [
      link(:video_source)
      |> to(:video_parser)
      |> to(:video_payloader)
      |> via_in(Pad.ref(:input, 1))
      |> to(:muxer),
      link(:audio_source)
      |> to(:audio_encoder)
      |> to(:audio_parser)
      |> via_in(Pad.ref(:input, 2))
      |> to(:muxer),
      link(:muxer) |> to(:file_sink)
    ]

    {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
  end

  @impl true
  def handle_element_end_of_stream({:file_sink, _}, _ctx, state) do
    Membrane.Pipeline.terminate(self())
    {:ok, state}
  end

  def handle_element_end_of_stream(element, _ctx, state) do
    {:ok, state}
  end
end

ref =
  Example.start_link()
  |> elem(1)
  |> tap(&Membrane.Pipeline.play/1)
  |> then(&Process.monitor/1)

receive do
  {:DOWN, ^ref, :process, _pid, _reason} ->
    :ok
end
