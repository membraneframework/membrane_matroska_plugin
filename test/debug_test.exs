defmodule Membrane.WebM.DebugTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.WebM.DebugTest.PrinterPipeline
  alias Membrane.Testing

  @tag :tmp_dir
  test "print file", %{tmp_dir: tmp_dir} do
    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: PrinterPipeline,
        custom_args: %{
          input_file: "test/fixtures/output.webm",
          output_dir: tmp_dir
        }
      }
      |> Testing.Pipeline.start_link()

    Testing.Pipeline.play(pipeline)
    # long timeout for dumping huge prints to file
    assert_end_of_stream(pipeline, :sink, :input, 60_000)
    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
  end
end
