defmodule Membrane.WebM.Demuxer do
  use Membrane.Filter

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
    IO.puts("initializing Demuxer")
    state = %{counter: 0}
    {:ok, state}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _context, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(:input, buffer, _context, state) do
    if state.counter == 0 do
      byte_string = buffer.payload
      |> Base.encode16

      hexdump(byte_string)
    end
    new_state = %{state | counter: state.counter + 1}
    {{:ok, buffer: {:output, buffer}}, new_state}
  end

  def hexdump(byte_string) do
    # byte_string
    # |> String.length
    # |> IO.inspect

    byte_string
    |> String.codepoints()
    |> Enum.chunk_every(4)
    |> Enum.intersperse(" ")
    |> Enum.chunk_every(8*2)
    |> Enum.intersperse("\n")
    |> IO.puts()
  end

end
