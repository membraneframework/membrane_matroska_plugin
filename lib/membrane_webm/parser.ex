defmodule Membrane.WebM.Parser do
  use Membrane.Filter

  alias Membrane.WebM.Parser.Element
  alias Membrane.Buffer

  def_input_pad :input,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers,
    caps: :any

  def_output_pad :output,
    availability: :always,
    mode: :pull,
    caps: :any

  def_options debug: [
                spec: boolean,
                default: false,
                description: "Print hexdump of input file"
              ],
              output_as_string: [
                spec: boolean,
                default: false,
                description:
                  "Output parsed WebM as a pretty-formatted string for dumping to file etc."
              ]

  @impl true
  def handle_init(options) do
    {:ok, %{options: options}}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _context, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(:input, buffer, _context, state) do
    IO.inspect(buffer.payload)
    if state.options.debug do
      debug_hexdump(buffer.payload)
    end

    output =
      buffer.payload
      |> Element.parse_list([])

    output =
      if state.options.output_as_string do
        inspect(output, limit: :infinity, pretty: true)
      else
        output
      end

    {{:ok, buffer: {:output, %Buffer{payload: output}}}, state}
  end

  def debug_hexdump(bytes) do
    bytes
    |> Base.encode16()
    |> String.codepoints()
    |> Enum.chunk_every(4)
    |> Enum.intersperse(" ")
    |> Enum.chunk_every(8 * 2)
    |> Enum.intersperse("\n")
    |> Enum.take(80)
    |> IO.puts()
  end
end

# demuxer and parser combo:
# 1 identify tracks and send caps info to pipeline
# 2 pluck out packets from partially parsed stream and send packets as you get them
# 3 notify parent youre done


# def handle_process(:input, buffer, _context, state) do
#   parse_chunk

#   need more?
#   {demand: {:input, 1}}
#   else
#   {buffer: {:output, b}}
# end

# def parse_chunk(bytes, accumulator) do
#   {:needs_more_data}

# end
