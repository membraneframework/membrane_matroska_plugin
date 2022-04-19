defmodule Membrane.WebM.DebugTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.WebM.DebugTest.PrinterPipeline
  alias Membrane.Testing

  @tag :tmp_dir
  test "print file 1", %{tmp_dir: tmp_dir} do
    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: PrinterPipeline,
        custom_args: %{
          # input_file: "test/fixtures/output_h264.mkv",
          # input_file: "test/fixtures/combined_h264.mkv",
          input_file: "test/fixtures/combined_h264_ffmpeg.mkv",
          # input_file: "test/fixtures/combined.mkv",
          output_dir: tmp_dir
        }
      }
      |> Testing.Pipeline.start_link()

    Testing.Pipeline.play(pipeline)
    # long timeout for dumping huge prints to file
    assert_end_of_stream(pipeline, :sink, :input, 60_000)
    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
  end

  # @tag :tmp_dir
  # test "print file 2", %{tmp_dir: tmp_dir} do
  #   {:ok, pipeline} =
  #     %Testing.Pipeline.Options{
  #       module: PrinterPipeline,
  #       custom_args: %{
  #         input_file: "tmp/output.mkv",
  #         output_dir: tmp_dir
  #       }
  #     }
  #     |> Testing.Pipeline.start_link()

  #   Testing.Pipeline.play(pipeline)
  #   # long timeout for dumping huge prints to file
  #   assert_end_of_stream(pipeline, :sink, :input, 60_000)
  #   Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
  # end
end
