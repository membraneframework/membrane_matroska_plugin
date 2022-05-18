defmodule Membrane.Matroska.DebugTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.Testing

  defmodule PrinterPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(options) do
      children = [
        source: %Membrane.File.Source{
          location: options.input_file,
          chunk_size: 4096
        },
        printer: Membrane.Matroska.Printer,
        sink: %Membrane.File.Sink{
          location: Path.join(options.output_dir, "output.ex")
        }
      ]

      links = [
        link(:source)
        |> to(:printer)
        |> to(:sink)
      ]

      {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
    end
  end

  @tag :tmp_dir
  test "print file", %{tmp_dir: tmp_dir} do
    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: PrinterPipeline,
        custom_args: %{
          input_file: "test/fixtures/combined_h264_flv_ffmpeg.mkv",
          # input_file: "tmp/output_h264.mkv",
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
