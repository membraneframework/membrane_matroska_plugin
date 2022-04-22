defmodule Membrane.WebM.DebugTest.PrinterPipeline do
  @moduledoc false
  use Membrane.Pipeline

  @impl true
  def handle_init(options) do
    output_file = Path.basename(options.input_file) <> ".ex"

    children = [
      source: %Membrane.File.Source{
        location: options.input_file,
        chunk_size: 4096
      },
      printer: Membrane.WebM.Printer,
      sink: %Membrane.File.Sink{
        location: Path.join(options.output_dir, output_file)
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
