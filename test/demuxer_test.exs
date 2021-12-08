defmodule Membrane.WebM.DemuxerTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.Testing

  @input_dir "./test/fixtures/"
  @output_dir "./test/results/"

  defmodule TestPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(options) do
      children = [
        source: %Membrane.File.Source{
          location: options.input_file,
          chunk_size: 4096
        },
        parser: Membrane.WebM.Parser,
        demuxer: Membrane.WebM.Demuxer
      ]

      links = [
        link(:source)
        |> to(:parser)
        |> to(:demuxer)
      ]

      {{:ok, spec: %ParentSpec{children: children, links: links}},
       %{output_dir: options.output_dir}}
    end

    @impl true
    def handle_notification({:new_track, {track_id, track_info}}, :demuxer, _context, state) do
      cond do
        track_info.codec == :opus ->
          children = %{
            # {:decoder, track_id} => Membrane.Opus.Decoder,
            # {:converter, track_id} => %Membrane.FFmpeg.SWResample.Converter{
            #   output_caps: %Membrane.Caps.Audio.Raw{
            #     format: :s16le,
            #     sample_rate: 48000,
            #     channels: 2
            #   }
            # },
            # {:portaudio, track_id} => Membrane.PortAudio.Sink,
            {:payloader, track_id} => %Membrane.Ogg.Payloader.Opus{
              frame_size: 20,
              random_serial_number?: false
            },
            {:sink, track_id} => %Membrane.File.Sink{
              location: state.output_dir <> "#{track_id}.ogg"
            }
          }

          links = [
            link(:demuxer)
            |> via_out(Pad.ref(:output, track_id))
            # |> to({:decoder, track_id})
            # |> to({:converter, track_id})
            # |> to({:portaudio, track_id})
            |> to({:payloader, track_id})
            |> to({:sink, track_id})
          ]

          {{:ok, spec: %ParentSpec{children: children, links: links}}, state}

        track_info.codec in [:vp8, :vp9] ->
          codec = Atom.to_string(track_info.codec)

          children = %{
            {:serializer, track_id} => %Membrane.Element.IVF.Serializer{
              rate: track_info.rate,
              scale: track_info.scale
            },
            {:sink, track_id} => %Membrane.File.Sink{
              location: state.output_dir <> "#{track_id}_#{codec}.ivf"
            }
          }

          links = [
            link(:demuxer)
            |> via_out(Pad.ref(:output, track_id))
            |> to({:serializer, track_id})
            |> to({:sink, track_id})
          ]

          {{:ok, spec: %ParentSpec{children: children, links: links}}, state}
      end
    end
  end

  test "demuxing webm containing opus" do
    test_stream("opus_audio.webm", ["1.ogg"], ["1.ogg"])
  end

  test "demuxing webm containing vp8 + opus" do
    test_stream("vp8_opus_video.webm", ["1_vp8.ivf", "2.ogg"], ["1_vp8.ivf", "2.ogg"])
  end

  test "demuxing webm containing vp9 + opus" do
    test_stream("vp9_opus_video.webm", ["1_vp9.ivf", "2.ogg"], ["1_vp9.ivf", "2.ogg"])
  end

  defp test_stream(input_file, references, results) do
    args = Enum.zip(references, results)

    if !File.exists?(@output_dir) do
      File.mkdir!(@output_dir)
    end

    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: TestPipeline,
        custom_args: %{
          input_file: @input_dir <> input_file,
          output_dir: @output_dir
        }
      }
      |> Testing.Pipeline.start_link()

    Testing.Pipeline.play(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :playing)

    if Enum.count(args) == 1 do
      assert_end_of_stream(pipeline, {:sink, 1})
    else
      assert_end_of_stream(pipeline, {:sink, 1})
      assert_end_of_stream(pipeline, {:sink, 2})
    end

    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
    assert_pipeline_playback_changed(pipeline, _, :stopped)

    for {reference, result} <- args do
      assert File.read!(@input_dir <> reference) ==
               File.read!(@output_dir <> result)
    end
  end
end
