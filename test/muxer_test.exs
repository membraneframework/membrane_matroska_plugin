defmodule Membrane.WebM.MuxerTest do
  # note that input pad ids should be set to a random value:
  # :random.uniform(1 <<< 64)
  # here numbers are hardcoded to achieve reproducibility

  use ExUnit.Case
  use Bitwise

  require Membrane.Pad

  import Membrane.ParentSpec
  import Membrane.Testing.Assertions
  alias Membrane.Testing
  alias Membrane.{Buffer, Opus, Pad}

  @fixtures_dir "./test/fixtures/"
  @pad_id_1 17_447_232_417_024_423_937
  @pad_id_2 13_337_737_628_113_408_001
  @pad_id_3 11_020_961_587_148_742_657
  @pad_id_4 16_890_875_709_512_990_721

  defp test_from_buffers(tmp_dir) do
    output_file = Path.join(tmp_dir, "output_webm")
    reference_file = Path.join(@fixtures_dir, "muxed_opus.webm")

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
          deserializer: Membrane.Element.IVF.Deserializer,
          muxer: Membrane.WebM.Muxer,
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
    output_file = Path.join(tmp_dir, "output.webm")
    reference_file = Path.join(@fixtures_dir, reference_file)

    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        elements: [
          source: %Membrane.File.Source{
            location: input_file
          },
          deserializer: Membrane.Element.IVF.Deserializer,
          muxer: Membrane.WebM.Muxer,
          sink: %Membrane.File.Sink{
            location: output_file
          }
        ],
        links: [
          link(:source)
          |> to(:deserializer)
          |> via_in(Pad.ref(:input, 13_337_737_628_113_408_001))
          |> to(:muxer)
          |> to(:sink)
        ]
      }
      |> Testing.Pipeline.start_link()

    play_and_validate(pipeline, reference_file, output_file)
  end

  defp test_many(tmp_dir) do
    input_file = Path.join(@fixtures_dir, "1_vp8.ivf")
    output_file = Path.join(tmp_dir, "output.webm")
    reference_file = Path.join(@fixtures_dir, "combined.webm")

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
          muxer: Membrane.WebM.Muxer,
          sink: %Membrane.File.Sink{
            location: output_file
          }
        ],
        links: [
          link(:vpx_source)
          |> to(:deserializer)
          |> via_in(Pad.ref(:input, 11_020_961_587_148_742_657))
          |> to(:muxer),
          link(:opus_source)
          |> via_in(Pad.ref(:input, 16_890_875_709_512_990_721))
          |> to(:muxer),
          link(:muxer)
          |> to(:sink)
        ]
      }
      |> Testing.Pipeline.start_link()

    play_and_validate(pipeline, reference_file, output_file)
  end

  defp play_and_validate(pipeline, reference_file, output_file) do
    Testing.Pipeline.play(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :playing)
    assert_start_of_stream(pipeline, :sink, :input, 100_000)
    assert_end_of_stream(pipeline, :sink, :input, 100_000)
    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
    assert_pipeline_playback_changed(pipeline, _, :stopped)
    assert File.read!(reference_file) == File.read!(output_file)
  end

  @tag :tmp_dir
  test "mux single vp8", %{tmp_dir: tmp_dir} do
    test_stream("1_vp8.ivf", "muxed_vp8.webm", tmp_dir)
  end

  @tag :tmp_dir
  test "mux single vp9", %{tmp_dir: tmp_dir} do
    test_stream("1_vp9.ivf", "muxed_vp9.webm", tmp_dir)
  end

  @tag :tmp_dir
  test "mux opus from buffers", %{tmp_dir: tmp_dir} do
    test_from_buffers(tmp_dir)
  end

  @tag :tmp_dir
  test "mux two streams into one file", %{tmp_dir: tmp_dir} do
    test_many(tmp_dir)
  end
end
