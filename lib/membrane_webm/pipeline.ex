defmodule Membrane.WebM.Pipeline do
  use Membrane.Pipeline

  # @file_name "tracks"

  @impl true
  def handle_init(_) do
    children = [
      # source: %Membrane.File.Source{location: Path.join([File.cwd!, "_stuff", "libwebm", "testing", "testdata", @file_name <> ".webm"]), chunk_size: 1048576},
      source: %Membrane.File.Source{location: Path.join([File.cwd!, "_stuff", "short2.webm"]), chunk_size: 1114194304},
      parser: %Membrane.WebM.Parser{debug: false, output_as_string: false},
      demuxer: Membrane.WebM.Demuxer,
      # decoder: Membrane.Opus.Decoder,
      # converter: %Membrane.FFmpeg.SWResample.Converter{
      #   output_caps: %Membrane.Caps.Audio.Raw{
      #     format: :s16le,
      #     sample_rate: 48000,
      #     channels: 2
      #   }
      # },
      # portaudio: Membrane.PortAudio.Sink,
      sink: %Membrane.File.Sink{location: Path.join([File.cwd!, "_stuff", "attempt" <> ".opus"])}
    ]
    links = [
      link(:source)
      |> to(:parser)
      |> to(:demuxer)
      # |> to(:decoder)
      # |> to(:converter)
      # |> to(:portaudio)
      |> to(:sink)
    ]
    {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
  end
end

# #! test
# Membrane.WebM.Pipeline.start_link()
# |> elem(1)
# |> tap(&Membrane.Pipeline.play/1)
# |> then(&Process.monitor/1)
