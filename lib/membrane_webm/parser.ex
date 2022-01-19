defmodule Membrane.WebM.Parser do
  @moduledoc """
  Implementation of a standalone parser of a webm bytestream (you shouldn't need to use this, no other element uses this).
  """
  use Membrane.Filter

  alias Membrane.Buffer
  alias Membrane.WebM.Parser.Helper

  def_input_pad :input,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers,
    caps: :any

  def_output_pad :output,
    availability: :always,
    mode: :pull,
    caps: :any

  @impl true
  def handle_init(_) do
    {:ok, %{acc: <<>>, header_consumed: false}}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _context, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload}, _context, %{
        acc: acc,
        header_consumed: header_consumed
      }) do
    unparsed = payload <> acc
    {parsed, unparsed, header_consumed} = Helper.parse(unparsed, header_consumed)

    {{:ok, [{:buffer, {:output, to_buffers(parsed)}}, {:demand, {:input, 1}}]},
     %{acc: unparsed, header_consumed: header_consumed}}
  end

  defp to_buffers(elements) do
    Enum.reduce(elements, [], fn {name, data}, acc ->
      [%Buffer{payload: data, metadata: %{webm: %{element_name: name}}} | acc]
    end)
  end
end
