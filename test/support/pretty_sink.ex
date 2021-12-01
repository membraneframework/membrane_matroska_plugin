# TO BE REMOVED - FOR DEBUGGING ONLY

defmodule Membrane.WebM.Debug.PrettySink do
  use Membrane.Bin

  alias Membrane.File.Sink
  alias Membrane.WebM.Debug.Parser

  def_options location: [
                spec: String.t(),
                default: "output.parsed",
                description: "Output file path + `name`"
              ]

  def_input_pad :input,
    demand_unit: :buffers,
    caps: :any,
    availability: :always

  @impl true
  def handle_init(options) do
    children = [
      parser: %Parser{
        debug: false,
        verbose: true
      },
      sink: %Sink{
        location: options.location
      }
    ]

    links = [
      link_bin_input(:input)
      |> to(:parser)
      |> to(:sink)
    ]

    state = %{}

    {{:ok, spec: %ParentSpec{children: children, links: links}}, state}
  end

  @impl true
  def handle_element_end_of_stream({:sink, _}, _ctx, state) do
    {{:ok, notify: :end_of_stream}, state}
  end

  def handle_element_end_of_stream(_element, _ctx, state) do
    {:ok, state}
  end
end
