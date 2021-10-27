defmodule Membrane.WebM.Pipeline do
  use Membrane.Pipeline

  # @file_name "tracks"

  @impl true
  def handle_init(_) do
    children = [
      source: %Membrane.File.Source{
        location: Path.join([File.cwd!(), "test", "fixtures", "short_vp8_opus.webm"]),
        chunk_size: 1_114_194_304
      },
      parser: %Membrane.WebM.Parser{debug: false, output_as_string: false},
      demuxer: %Membrane.WebM.Demuxer{output_as_string: true},
      # serializer: %Membrane.Element.IVF.Serializer{
      #   width: 1920,
      #   height: 1080,
      #   rate: 1000,
      #   scale: 1
      # },
      # decoder: Membrane.Opus.Decoder,
      # converter: %Membrane.FFmpeg.SWResample.Converter{
      #   output_caps: %Membrane.Caps.Audio.Raw{
      #     format: :s16le,
      #     sample_rate: 48000,
      #     channels: 2
      #   }
      # },
      # portaudio: Membrane.PortAudio.Sink,
      sink: %Membrane.File.Sink{location: Path.join([File.cwd!(), "_stuff", "tracks.parsed"])}
    ]

    links = [
      link(:source)
      |> to(:parser)
      |> to(:demuxer)
      # |> to(:serializer)
      # |> to(:decoder)
      # |> to(:converter)
      # |> to(:portaudio)
      |> to(:sink)
    ]

    {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
  end

  def handle_notification({:pad_added, info}, :demuxer, _context, state) do
    IO.inspect(info)
    {:ok, state}
  end
end
