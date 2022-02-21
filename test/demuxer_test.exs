defmodule Membrane.WebM.DemuxerTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.Testing

  @fixtures_dir "./test/fixtures/"

  defmodule TestPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(options) do
      children = [
        source: %Membrane.File.Source{
          location: options.input_file,
          chunk_size: 4096
        },
        demuxer: Membrane.WebM.Demuxer
      ]

      links = [
        link(:source)
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
            {:payloader, track_id} => %Membrane.Ogg.Payloader.Opus{
              frame_size: 20,
              serial_number: 4_210_672_757
            },
            {:sink, track_id} => %Membrane.File.Sink{
              location: Path.join(state.output_dir, "#{track_id}.ogg")
            }
          }

          links = [
            link(:demuxer)
            |> via_out(Pad.ref(:output, track_id))
            |> to({:payloader, track_id})
            |> to({:sink, track_id})
          ]

          {{:ok, spec: %ParentSpec{children: children, links: links}}, state}

        track_info.codec in [:vp8, :vp9] ->
          codec = Atom.to_string(track_info.codec)

          children = %{
            {:serializer, track_id} => Membrane.Element.IVF.Serializer,
            {:sink, track_id} => %Membrane.File.Sink{
              location: Path.join(state.output_dir, "#{track_id}_#{codec}.ivf")
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

  defp test_stream(input_file, references, tmp_dir) do
    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: TestPipeline,
        custom_args: %{
          input_file: Path.join(@fixtures_dir, input_file),
          output_dir: tmp_dir
        }
      }
      |> Testing.Pipeline.start_link()

    Testing.Pipeline.play(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :playing)

    if Enum.count(references) == 1 do
      assert_end_of_stream(pipeline, {:sink, 1})
    else
      assert_end_of_stream(pipeline, {:sink, 1})
      assert_end_of_stream(pipeline, {:sink, 2})
    end

    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
    assert_pipeline_playback_changed(pipeline, _, :stopped)

    for reference <- references do
      assert File.read!(Path.join(@fixtures_dir, reference)) ==
               File.read!(Path.join(tmp_dir, reference))
    end
  end

  @tag :tmp_dir
  setup %{tmp_dir: tmp_dir} do
    on_exit(fn -> File.rm_rf!(tmp_dir); :ok end)
  end

  @tag :tmp_dir
  test "demuxing webm containing opus", %{tmp_dir: tmp_dir} do
    test_stream("muxed_opus.webm", ["1.ogg"], tmp_dir)
  end

  @tag :tmp_dir
  test "demuxing webm containing vp8 + opus", %{tmp_dir: tmp_dir} do
    test_stream("vp8_opus_video.webm", ["1_vp8.ivf", "2.ogg"], tmp_dir)
  end

  @tag :tmp_dir
  test "demuxing webm containing vp9 + opus", %{tmp_dir: tmp_dir} do
    test_stream("vp9_opus_video.webm", ["1_vp9.ivf", "2.ogg"], tmp_dir)
  end
end
