defmodule Membrane.WebM.DemuxerPipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_) do
    children = [
      source: %Membrane.File.Source{
        location: Path.join([File.cwd!(), "test", "fixtures", "sample_opus.webm"]),
        chunk_size: 1_114_194_304
      },
      parser: %Membrane.WebM.Parser{debug: false, output_as_string: false},
      demuxer: Membrane.WebM.Demuxer,
    ]

    links = [
      link(:source)
      |> to(:parser)
      |> to(:demuxer)
    ]

    {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
  end

  @impl true
  def handle_notification({:new_channel, {channel_id, details}}, :demuxer, _context, state) do
    case details.codec do
      :opus ->
        children = %{
          {:decoder, channel_id} => Membrane.Opus.Decoder,
          {:converter, channel_id} => %Membrane.FFmpeg.SWResample.Converter{
            output_caps: %Membrane.Caps.Audio.Raw{
              format: :s16le,
              sample_rate: 48000,
              channels: 2
            }
          },
          {:portaudio, channel_id} => Membrane.PortAudio.Sink,
          # {:sink, channel_id} => %Membrane.File.Sink{
          #   location: "test/results/#{channel_id}_opus.opus"
          # }
        }

        links = [
          link(:demuxer)
          |> via_out(Pad.ref(:output, channel_id))
          |> to({:decoder, channel_id})
          |> to({:converter, channel_id})
          |> to({:portaudio, channel_id})
          # |> to({:sink, channel_id})
        ]

        {{:ok, spec: %ParentSpec{children: children, links: links}}, state}

      :vp8 ->
        children = %{
          {:serializer, channel_id} => %Membrane.Element.IVF.Serializer{
            width: details.width,
            height: details.height,
            rate: details.rate,
            scale: details.scale
          },
          {:sink, channel_id} => %Membrane.File.Sink{
            location: "test/results/#{channel_id}_vp8.ivf"
          }
        }

        links = [
          link(:demuxer)
          |> via_out(Pad.ref(:output, channel_id))
          |> to({:serializer, channel_id})
          |> to({:sink, channel_id})
        ]

        {{:ok, spec: %ParentSpec{children: children, links: links}}, state}

      :vp9 ->
        children = %{
          {:serializer, channel_id} => %Membrane.Element.IVF.Serializer{
            width: details.width,
            height: details.height,
            rate: details.rate,
            scale: details.scale
          },
          {:sink, channel_id} => %Membrane.File.Sink{
            location: "test/results/#{channel_id}_vp9.ivf"
          }
        }

        links = [
          link(:demuxer)
          |> via_out(Pad.ref(:output, channel_id))
          |> to({:serializer, channel_id})
          |> to({:sink, channel_id})
        ]

        {{:ok, spec: %ParentSpec{children: children, links: links}}, state}
    end
  end
end
