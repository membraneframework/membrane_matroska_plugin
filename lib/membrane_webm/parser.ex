defmodule Membrane.WebM.Parser do
  use Membrane.Filter

  alias Membrane.{Buffer, Time}
  alias Membrane.WebM.Parser.Vint
  alias Membrane.WebM.Schema

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

    if state.options.debug do
      debug_hexdump(buffer.payload)
    end

    output =
      buffer.payload
      |> parse_list([])

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

  def parse_list(bytes, acc) do
    %{element: element, rest: bytes} = parse_element(bytes)
    acc = [element | acc]

    if bytes == <<>> do
      acc
    else
      parse_list(bytes, acc)
    end
  end

  def parse(bytes, :master, _name) do
    if byte_size(bytes) == 0 do
      []
    else
      parse_list(bytes, [])
    end
  end

  def parse(bytes, :uint, :TrackType) do
    <<int::unsigned-integer-size(8)>> = bytes

    case int do
      1 -> :video
      2 -> :audio
      3 -> :complex
      16 -> :logo
      17 -> :subtitle
      18 -> :buttons
      32 -> :control
      33 -> :metadata
    end
  end

  def parse(bytes, :uint, :FlagInterlaced) do
    <<int::unsigned-integer-size(8)>> = bytes

    case int do
      # Unknown status.This value SHOULD be avoided.
      0 -> :undetermined
      # Interlaced frames.
      1 -> :interlaced
      # No interlacing.
      2 -> :progressive
    end
  end

  def parse(bytes, :uint, :ChromaSitingHorz) do
    <<int::unsigned-integer-size(8)>> = bytes

    case int do
      0 -> :unspecified
      1 -> :left_collocated
      2 -> :half
    end
  end

  def parse(bytes, :uint, :ChromaSitingVert) do
    <<int::unsigned-integer-size(8)>> = bytes

    case int do
      0 -> :unspecified
      1 -> :top_collocated
      2 -> :half
    end
  end

  def parse(<<>>, :uint, _name) do
    0
  end

  def parse(bytes, :uint, _name) do
    :binary.decode_unsigned(bytes, :big)
  end

  def parse(<<>>, :integer, _name) do
    0
  end

  def parse(bytes, :integer, _name) do
    s = byte_size(bytes) * 8
    <<num::signed-big-integer-size(s)>> = bytes
    num
  end

  def parse(<<>>, :float, _name) do
    0
  end

  def parse(<<num::float-big>>, :float, _name) do
    num
  end

  def parse(bytes, :binary, :SimpleBlock) do
    # https://tools.ietf.org/id/draft-lhomme-cellar-matroska-04.html#rfc.section.6.2.4.4

    # track_number is a vint with size 1 or 2 bytes
    %{vint: track_number_vint, rest: bytes} = Vint.parse(bytes)
    <<timecode::integer-signed-size(16), flags::bitstring-size(8), data::binary>> = bytes
    <<keyframe::1, reserved::3, invisible::1, lacing::2, discardable::1>> = flags

    if reserved != 0 do
      IO.puts("SimpleBlock reserved bits in header flag should all be 0 but they are #{reserved}")
    end

    lacing =
      case lacing do
        0b00 -> :no_lacing
        0b01 -> :Xiph_lacing
        0b11 -> :EBML_lacing
        0b10 -> :fixed_size_lacing
      end

    # TODO deal with lacing != 00 https://tools.ietf.org/id/draft-lhomme-cellar-matroska-04.html#laced-data-1

    %{
      track_number: track_number_vint.vint_data,
      timecode: timecode,
      header_flags: %{
        keyframe: keyframe == 1,
        reserved: reserved,
        invisible: invisible == 1,
        lacing: lacing,
        discardable: discardable == 1
      },
      data: data
    }
  end

  def parse(bytes, :binary, _name) do
    bytes
    # Base.encode16(bytes)
  end

  def parse(bytes, :string, :CodecID) do
    # Video	    “V_*”
    # Audio	    “A_*”
    # Subtitle  “S_*”
    # Button	  “B_*”
    codec_string = Enum.join(for <<c::utf8 <- bytes>>, do: <<c::utf8>>)

    case codec_string do
      "A_OPUS" -> :opus
      "A_VORBIS" -> :vorbis
      "V_VP8" -> :vp8
      "V_VP9" -> :vp9
      _ -> raise "Invalid codec: #{codec_string}"
    end
  end

  def parse(bytes, :string, _name) do
    chars = for <<c::utf8 <- bytes>>, do: <<c::utf8>>
    chars |> Enum.take_while(fn c -> c != <<0>> end) |> Enum.join()
  end

  def parse(bytes, :utf_8, _name) do
    bytes
    |> String.codepoints()
    |> Enum.reduce("", fn codepoint, result ->
      <<parsed::8>> = codepoint
      if parsed == 0, do: result, else: result <> <<parsed>>
    end)
  end

  def parse(<<>>, :date, _name) do
    {{2001, 1, 1}, {0, 0, 0}}
  end

  def parse(<<nanoseconds::big-signed>>, :date, _name) do
    seconds_zero = :calendar.datetime_to_gregorian_seconds({{2001, 1, 1}, {0, 0, 0}})
    seconds = div(nanoseconds, Time.nanosecond()) + seconds_zero
    :calendar.gregorian_seconds_to_datetime(seconds)
  end

  def parse(bytes, :void, _name) do
    # Base.encode16(bytes)
    byte_size(bytes)
  end

  def parse(bytes, :unknown, _name) do
    Base.encode16(bytes)
  end

  def parse(bytes, :ignore, _name) do
    Base.encode16(bytes)
  end

  def parse_element(bytes) do
    %{vint: vint, rest: bytes} = Vint.parse(bytes)
    id = vint.element_id
    %{vint: vint, rest: bytes} = Vint.parse(bytes)
    data_size = vint.vint_data
    # TODO: deal with unknown data size
    {name, type} = Schema.classify_element(id)

    if name == :Unknown do
      IO.puts("unknown element ID: #{id}")
    end

    with %{bytes: data, rest: bytes} <- trim_bytes(bytes, data_size) do
      element = {
        name,
        # parse(data, type, name)
        # %{
          # data_size: data_size,
          parse(data, type, name)
          # type: type
        # }
      }

      %{element: element, rest: bytes}
    end
  end

  def trim_bytes(bytes, how_many) do
    <<bytes::binary-size(how_many), rest::binary>> = bytes
    %{bytes: bytes, rest: rest}
  end
end

#! demuxer and parser combo:
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
