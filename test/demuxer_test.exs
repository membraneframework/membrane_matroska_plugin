defmodule Membrane.Matroska.DemuxerTest do
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
        demuxer: Membrane.Matroska.Demuxer
      ]

      links = [
        link(:source)
        |> to(:demuxer)
      ]

      state = %{output_dir: options.output_dir, track_id_to_file: options.track_id_to_output_file}

      {{:ok, spec: %ParentSpec{children: children, links: links}}, state}
    end

    @impl true
    def handle_notification({:new_track, {track_id, track_info}}, :demuxer, _context, state) do
      output_file = state.track_id_to_file[track_id]

      cond do
        track_info.codec == :opus ->
          children = %{
            {:payloader, track_id} => %Membrane.Ogg.Payloader.Opus{
              frame_size: 20,
              serial_number: 4_210_672_757
            },
            {:sink, track_id} => %Membrane.File.Sink{
              location: Path.join(state.output_dir, output_file)
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
            {:serializer, track_id} => %Membrane.Element.IVF.Serializer{width: 1920, height: 1080},
            {:sink, track_id} => %Membrane.File.Sink{
              location: Path.join(state.output_dir, output_file)
            }
          }

          links = [
            link(:demuxer)
            |> via_out(Pad.ref(:output, track_id))
            |> to({:serializer, track_id})
            |> to({:sink, track_id})
          ]

          {{:ok, spec: %ParentSpec{children: children, links: links}}, state}

        track_info.codec == :h264 ->
          codec = Atom.to_string(track_info.codec)

          children = %{
            :parser => %Membrane.H264.FFmpeg.Parser{
              skip_until_parameters?: false,
              attach_nalus?: true
            },
            {:sink, track_id} => %Membrane.File.Sink{
              location: Path.join(state.output_dir, output_file)
            }
          }

          links = [
            link(:demuxer)
            |> via_out(Pad.ref(:output, track_id))
            |> to(:parser)
            |> to({:sink, track_id})
          ]

          {{:ok, spec: %ParentSpec{children: children, links: links}}, state}

        true ->
          raise "Unsupported codec #{track_info.codec}"
      end
    end
  end

  defp test_stream(input_file, track_id_to_reference, tmp_dir) do
    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: TestPipeline,
        custom_args: %{
          input_file: Path.join(@fixtures_dir, input_file),
          output_dir: tmp_dir,
          track_id_to_output_file: track_id_to_reference
        }
      }
      |> Testing.Pipeline.start_link()

    Testing.Pipeline.play(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :playing)

    references = Map.values(track_id_to_reference)

    if Enum.count(references) == 1 do
      assert_end_of_stream(pipeline, {:sink, 1})
    else
      assert_end_of_stream(pipeline, {:sink, 1}, :input)
      assert_end_of_stream(pipeline, {:sink, 2}, :input)
    end

    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
    assert_pipeline_playback_changed(pipeline, _, :stopped)

    for reference <- Map.values(track_id_to_reference) do
      reference_file = File.read!(Path.join(@fixtures_dir, reference))
      result_file = File.read!(Path.join(tmp_dir, reference))

      assert byte_size(reference_file) == byte_size(result_file),
             "#{reference} #{byte_size(reference_file)} == #{byte_size(result_file)}"

      assert reference_file == result_file, "#{reference} not same files"
    end
  end

  @tag :tmp_dir
  setup %{tmp_dir: tmp_dir} do
    on_exit(fn ->
      File.rm_rf!(tmp_dir)
      :ok
    end)
  end

  @tag :tmp_dir
  test "demuxing mkv containing opus", %{tmp_dir: tmp_dir} do
    test_stream("muxed_opus.mkv", %{1 => "1.ogg"}, tmp_dir)
  end

  @tag :tmp_dir
  test "demuxing mkv file (vp8,opus)", %{tmp_dir: tmp_dir} do
    test_stream("vp8_opus_video.mkv", %{1 => "2_vp8.ivf", 2 => "2.ogg"}, tmp_dir)
  end

  @tag :tmp_dir
  test "demuxing webm file (vp8,opus)", %{tmp_dir: tmp_dir} do
    test_stream("vp8_opus_video.webm", %{1 => "2_vp8.ivf", 2 => "2.ogg"}, tmp_dir)
  end

  @tag :tmp_dir
  test "demuxing muxed file (vp8,opus)", %{tmp_dir: tmp_dir} do
    test_stream("combined_vp8.mkv", %{2 => "1_vp8_demuxed.ivf", 1 => "1.ogg"}, tmp_dir)
  end

  @tag :tmp_dir
  test "demuxing mkv file (vp9,opus)", %{tmp_dir: tmp_dir} do
    test_stream("vp9_opus_video.mkv", %{1 => "1_vp9.ivf", 2 => "2.ogg"}, tmp_dir)
  end

  @tag :tmp_dir
  test "demuxing webm file (vp9,opus)", %{tmp_dir: tmp_dir} do
    test_stream("vp9_opus_video.webm", %{1 => "1_vp9.ivf", 2 => "2.ogg"}, tmp_dir)
  end

  @tag :tmp_dir
  test "demuxing mkv file (h264,opus)", %{tmp_dir: tmp_dir} do
    test_stream("h264_opus_video.mkv", %{1 => "video.h264", 2 => "2.ogg"}, tmp_dir)
  end

  @tag :tmp_dir
  test "demuxing muxed file (h264,opus)", %{tmp_dir: tmp_dir} do
    test_stream("combined_h264.mkv", %{2 => "video.h264", 1 => "1.ogg"}, tmp_dir)
  end
end
