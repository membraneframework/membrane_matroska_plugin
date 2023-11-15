Mix.install([
  :membrane_core,
  {:membrane_matroska_plugin, path: __DIR__ |> Path.join("..") |> Path.expand()},
  :membrane_hackney_plugin,
  :membrane_h264_plugin,
  :membrane_h264_format,
  :membrane_opus_plugin
])

# In this example, the pipeline will:
# - download audio and video files
# - conduct preprocessing of streams from files:
# 	  - encode audio stream to opus
# 	  - parse the H264 video stream and then payload it
# - create a matroska stream from the preprocessed streams
# - save the matroska stream to the file


defmodule Example do
  use Membrane.Pipeline

  alias Membrane.RawAudio

  @samples_url "https://raw.githubusercontent.com/membraneframework/static/gh-pages/samples/"
  @video_url @samples_url <> "ffmpeg-testsrc.h264"
  @audio_url @samples_url <> "beep-s16le-48kHz-stereo.raw"
  @output_file Path.expand("example_h264.mkv")

  @impl true
  def handle_init(_ctx, _options) do
    structure = [
      child(:video_source, %Membrane.Hackney.Source{
        location: @video_url,
        hackney_opts: [follow_redirect: true]
      })
      |> child(:video_parser, %Membrane.H264.Parser{
        generate_best_effort_timestamps: %{framerate: {30, 1}},
        output_stream_structure: :avc3
      })
      |> child(:muxer, Membrane.Matroska.Muxer),
      child(:audio_source, %Membrane.Hackney.Source{
        location: @audio_url,
        hackney_opts: [follow_redirect: true]
      })
      |> child(:audio_encoder, %Membrane.Opus.Encoder{
        application: :audio,
        input_stream_format: %RawAudio{
          channels: 2,
          sample_format: :s16le,
          sample_rate: 48_000
        }
      })
      |> child(:audio_parser, %Membrane.Opus.Parser{delimitation: :undelimit})
      |> get_child(:muxer)
      |> child(:file_sink, %Membrane.File.Sink{location: @output_file})
    ]

    {[spec: structure], %{}}
  end

  # Next two functions are only a logic for terminating a pipeline when it's done, you don't need to worry
  @impl true
  def handle_element_end_of_stream(:file_sink, _pad, _ctx, state) do
    {[terminate: :normal], state}
  end

  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end
end

{:ok, _supervisor, pipeline} = Example.start_link()
monitor_ref = Process.monitor(pipeline)

receive do
  {:DOWN, ^monitor_ref, :process, _pid, _reason} ->
    :ok
end
