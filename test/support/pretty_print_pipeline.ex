defmodule Membrane.WebM.PrettyPrintPipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_) do
    children = [
      source: %Membrane.File.Source{
        location: "test/fixtures/sample_opus.webm",
        chunk_size: 1_114_194_304
      },
      pretty_sink: %Membrane.WebM.Debug.PrettySink{location: "test/results/sample.pretty"}
    ]

    links = [
      link(:source)
      |> to(:pretty_sink)
    ]

    {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
  end

  def handle_notification(:end_of_stream, :pretty_sink, _context, state) do
    stop_and_terminate(self())
    {:ok, state}
  end
end
