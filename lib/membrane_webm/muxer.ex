defmodule Membrane.WebM.Muxer do
  use Membrane.Filter

  alias Membrane.WebM.Parser.Vint
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

  @impl true
  def handle_init(_) do
    {:ok, %{first: true}}
  end

  @impl true
  def handle_process(:input, buffer, _context, state) do
    IO.inspect(buffer)
    if state.first do
      newstate = %{first: false}
      ebml = assemble_ebml(nil)
      {{:ok, buffer: {:output, %Buffer{payload: ebml}}}, newstate}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_demand(:output, size, :buffers, _context, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  def serialize({name, %{data: data, data_size: data_size, type: type}}) do
    element_id = Base.decode16!(element_id(name))
    element_data_size = Vint.encode_number(data_size)
    element_data = encode(data, type, data_size)

    element_id <> element_data_size <> element_data
  end

  def serialize(elements) when is_list(elements) do
    Enum.reduce(elements, <<>>, fn element, acc -> acc <> serialize(element) end)
  end

  def encode(data, :master, _data_size) do
    serialize(data)
  end

  def encode(data, :uint, data_size) do
    length = 8 * data_size
    <<data::little-size(length)>>
  end

  def encode(data, :string, _data_size) do
    data
  end

  def assemble_ebml(_buffers) do
    #! lists get encoded in reverse order
    header = [
      EBML: %{
        data: [
          DocTypeReadVersion: %{data: 2, data_size: 1, type: :uint},
          DocTypeVersion: %{data: 4, data_size: 1, type: :uint},
          DocType: %{data: "webm", data_size: 4, type: :string},
          EBMLMaxSizeLength: %{data: 8, data_size: 1, type: :uint},
          EBMLMaxIDLength: %{data: 4, data_size: 1, type: :uint},
          EBMLReadVersion: %{data: 1, data_size: 1, type: :uint},
          EBMLVersion: %{data: 1, data_size: 1, type: :uint}
        ],
        data_size: 31,
        type: :master
      }
    ]
    serialize(header)
  end

  def element_id(name) do
    case name do
      ### EBML elements:
      :EBML -> "1A45DFA3"
      :EBMLVersion -> "4286"
      :EBMLReadVersion -> "42F7"
      :EBMLMaxIDLength -> "42F2"
      :EBMLMaxSizeLength -> "42F3"
      :DocType -> "4282"
      :DocTypeVersion -> "4287"
      :DocTypeReadVersion -> "4285"
      :DocTypeExtension -> "4281"
      :DocTypeExtensionName -> "4283"
      :DocTypeExtensionVersion -> "4284"
    end
  end
end
