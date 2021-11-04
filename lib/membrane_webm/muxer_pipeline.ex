defmodule Membrane.WebM.MuxerPipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_) do
    children = [
      source: %Membrane.File.Source{location: Path.join([File.cwd!(), "test", "fixtures", "vp8.ivf"])},
      deserializer: Membrane.Element.IVF.Deserializer,
      muxer: Membrane.WebM.Muxer,
      sink: %Membrane.File.Sink{location: "test/results/muxer"}
    ]

    links = [
      link(:source)
      |> to(:deserializer)
      |> to(:muxer)
      |> to(:sink)
    ]

    {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
  end
end
