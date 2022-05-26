defmodule Membrane.Matroska.Printer do
  @moduledoc """
  Implementation of a standalone parser of a mkv bytestream (you shouldn't need to use this, no other element uses this).
  """
  use Membrane.Filter

  alias Membrane.Buffer
  alias Membrane.Matroska.Parser.Helper

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
  def handle_init(_options) do
    {:ok, %{acc: <<>>}}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _context, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload}, _context, %{
        acc: acc
      }) do
    {{:ok, demand: {:input, 100}}, %{acc: acc <> payload}}
  end

  @impl true
  def handle_end_of_stream(:input, _context, %{acc: acc}) do
    {parsed, _unparsed} =
      Helper.parse(acc, &Membrane.Matroska.Schema.deserialize_webm_for_debug/1)

    {{:ok, buffer: {:output, to_buffers(parsed)}, end_of_stream: :output}, %{}}
  end

  defp to_buffers(elements) do
    Enum.reduce(elements, [], fn element, acc ->
      [%Buffer{payload: inspect(element, pretty: true, limit: :infinity)} | acc]
    end)
  end
end
