defmodule Membrane.Matroska.MuxerTest do
  # note that input pad ids should be set to a random value:
  # :random.uniform(1 <<< 64)
  # here numbers are hardcoded to achieve reproducibility

  use ExUnit.Case
  use Bitwise

  import Membrane.ParentSpec
  import Membrane.Testing.Assertions

  require Membrane.Pad

  alias Membrane.Testing
  alias Membrane.{Opus, FLV, Pad}

  @fixtures_dir "./test/fixtures/"
  @pad_id_1 17_447_232_417_024_423_937
  @pad_id_2 13_337_737_628_113_408_001
  @pad_id_3 11_020_961_587_148_742_657
  @pad_id_4 16_890_875_709_512_990_721
  @date DateTime.from_gregorian_seconds(63_821_112_726)

  defp test_from_buffers(tmp_dir) do
    output_file = Path.join(tmp_dir, "output_muxed_opus.mkv")
    reference_file = Path.join(@fixtures_dir, "muxed_opus.mkv")

    buffers =
      Path.join(@fixtures_dir, "buffers_dump.opus")
      |> File.read!()
      |> :erlang.binary_to_term()
      |> Enum.reverse()

    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        elements: [
          source: %Testing.Source{
            output: Testing.Source.output_from_buffers(buffers),
            caps: %Opus{channels: 2, self_delimiting?: false}
          },
          muxer: %Membrane.Matroska.Muxer{date: @date},
          sink: %Membrane.File.Sink{
            location: output_file
          }
        ],
        links: [
          link(:source)
          |> via_in(Pad.ref(:input, @pad_id_1))
          |> to(:muxer)
          |> to(:sink)
        ]
      }
      |> Testing.Pipeline.start_link()

    play_and_validate(pipeline, reference_file, output_file)
  end

  defp test_stream(input_file, reference_file, tmp_dir) do
    input_file = Path.join(@fixtures_dir, input_file)
    output_file = Path.join(tmp_dir, "output.mkv")
    reference_file = Path.join(@fixtures_dir, reference_file)

    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        elements: [
          source: %Membrane.File.Source{
            location: input_file
          },
          deserializer: Membrane.Element.IVF.Deserializer,
          muxer: %Membrane.Matroska.Muxer{date: @date},
          sink: %Membrane.File.Sink{
            location: output_file
          }
        ],
        links: [
          link(:source)
          |> to(:deserializer)
          |> via_in(Pad.ref(:input, @pad_id_2))
          |> to(:muxer)
          |> to(:sink)
        ]
      }
      |> Testing.Pipeline.start_link()

    play_and_validate(pipeline, reference_file, output_file)
  end

  defp test_many(tmp_dir, codec) when codec in [:vp8, :vp9] do
    input_file = Path.join(@fixtures_dir, "1_#{Atom.to_string(codec)}.ivf")
    output_file = Path.join(tmp_dir, "output_#{Atom.to_string(codec)}.mkv")
    reference_file = Path.join(@fixtures_dir, "combined_#{Atom.to_string(codec)}.mkv")

    buffers =
      Path.join(@fixtures_dir, "buffers_dump.opus")
      |> File.read!()
      |> :erlang.binary_to_term()
      |> Enum.reverse()

    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        elements: [
          vpx_source: %Membrane.File.Source{
            location: input_file
          },
          deserializer: Membrane.Element.IVF.Deserializer,
          opus_source: %Testing.Source{
            output: Testing.Source.output_from_buffers(buffers),
            caps: %Opus{channels: 2, self_delimiting?: false}
          },
          muxer: %Membrane.Matroska.Muxer{date: @date},
          sink: %Membrane.File.Sink{
            location: output_file
          }
        ],
        links: [
          link(:vpx_source)
          |> to(:deserializer)
          |> via_in(Pad.ref(:input, @pad_id_3))
          |> to(:muxer),
          link(:opus_source)
          |> via_in(Pad.ref(:input, @pad_id_4))
          |> to(:muxer),
          link(:muxer)
          |> to(:sink)
        ]
      }
      |> Testing.Pipeline.start_link()

    play_and_validate(pipeline, reference_file, output_file)
  end

  defp test_many(tmp_dir, :h264) do
    input_file = Path.join(@fixtures_dir, "h264.flv")
    output_file = Path.join(tmp_dir, "output_h264.mkv")
    reference_file = Path.join(@fixtures_dir, "combined_h264.mkv")

    buffers =
      Path.join(@fixtures_dir, "buffers_dump.opus")
      |> File.read!()
      |> :erlang.binary_to_term()
      |> Enum.reverse()

    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        elements: [
          h264_source: %Membrane.File.Source{
            location: input_file
          },
          flv_demuxer: FLV.Demuxer,
          parser: %Membrane.H264.FFmpeg.Parser{
            attach_nalus?: true,
            skip_until_parameters?: false
          },
          opus_source: %Testing.Source{
            output: Testing.Source.output_from_buffers(buffers),
            caps: %Opus{channels: 2, self_delimiting?: false}
          },
          mp4_payloader: Membrane.MP4.Payloader.H264,
          muxer: %Membrane.Matroska.Muxer{date: @date},
          sink: %Membrane.File.Sink{
            location: output_file
          }
        ],
        links: [
          link(:h264_source)
          |> to(:flv_demuxer)
          |> via_out(Pad.ref(:video, 0))
          |> to(:parser)
          |> to(:mp4_payloader)
          |> via_in(Pad.ref(:input, @pad_id_3))
          |> to(:muxer),
          link(:opus_source)
          |> via_in(Pad.ref(:input, @pad_id_4))
          |> to(:muxer),
          link(:muxer)
          |> to(:sink)
        ]
      }
      |> Testing.Pipeline.start_link()

    play_and_validate(pipeline, reference_file, output_file)
  end

  defp play_and_validate(pipeline, reference_file, output_file) do
    assert_pipeline_playback_changed(pipeline, :prepared, :playing)
    assert_start_of_stream(pipeline, :sink)
    assert_end_of_stream(pipeline, :sink)
    Testing.Pipeline.terminate(pipeline, blocking?: true)
    assert_pipeline_playback_changed(pipeline, :prepared, :stopped)

    reference_file = File.read!(reference_file)
    result_file = File.read!(output_file)

    fixtures_list = :binary.bin_to_list(reference_file)
    result_list = :binary.bin_to_list(result_file)

    zipped_with_indexes = fixtures_list |> Enum.zip(result_list) |> Enum.with_index()

    for {{elem1, elem2}, idx} = _elem <- zipped_with_indexes do
      if elem1 != elem2 do
        raise "#{elem1} is not equal #{elem2} on index #{idx}"
      end
    end

    assert byte_size(reference_file) == byte_size(result_file)
    assert reference_file == result_file
  end

  @tag :tmp_dir
  setup %{tmp_dir: tmp_dir} do
    on_exit(fn ->
      File.rm_rf!(tmp_dir)
      :ok
    end)
  end

  @tag :tmp_dir
  test "mux single vp8", %{tmp_dir: tmp_dir} do
    test_stream("1_vp8.ivf", "muxed_vp8.mkv", tmp_dir)
  end

  @tag :tmp_dir
  test "mux single vp9", %{tmp_dir: tmp_dir} do
    test_stream("1_vp9.ivf", "muxed_vp9.mkv", tmp_dir)
  end

  @tag :tmp_dir
  test "mux opus from buffers", %{tmp_dir: tmp_dir} do
    test_from_buffers(tmp_dir)
  end

  @tag :tmp_dir
  test "mux two streams (opus, vp8) into one file", %{tmp_dir: tmp_dir} do
    test_many(tmp_dir, :vp8)
  end

  @tag :tmp_dir
  test "mux two streams (opus, vp9) into one file", %{tmp_dir: tmp_dir} do
    test_many(tmp_dir, :vp9)
  end

  @tag :tmp_dir
  test "mux two streams (opus, h264) into one file", %{tmp_dir: tmp_dir} do
    test_many(tmp_dir, :h264)
  end
end
