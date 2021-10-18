defmodule Membrane.WebM.Parser.Element do
  @moduledoc """
  An EBML element consists of
  - element_id - a VINT
  - element_data_size - a VINT
  - element_data - which is another element
    - signed integer element
    - unsigned integer element
    - float element
    - string element
    - UTF-8 element
    - date element
    - binary element
      contents should not be interpreted by parser
    - master element
      A Master Element declare a length in octets from zero to VINTMAX or be of unknown
      length. See Section 6 for rules that apply to elements of unknown length.
      The Master Element contains zero or more other elements. EBML Elements contained within a
      Master Element have the EBMLParentPath of their Element Path equal to the
      EBMLFullPath of the Master Element Element Path (see Section 11.1.6.2). Element Data stored
      within Master Elements only consist of EBML Elements and contain any
      data that is not part of an EBML Element. The EBML Schema identifies what Element IDs are
      valid within the Master Elements for that version of the EBML Document Type. Any data
      contained within a Master Element that is not part of a Child Element be ignored.

  TODO element_id is the only type of VINT for which it is illegal to take up more space than is necessary i.e.
    1 0000001 is legal
    0 1 00000000000001 is illegal because a shorter encoding of VINT_DATA is available
    (it fits in 1 byte but 2 are used)

  element_data_size can be unknown!
    https://www.rfc-editor.org/rfc/rfc8794.pdf section 6.2
    craaayyyzy


  """

  alias Membrane.WebM.Parser.Vint
  alias Membrane.WebM.Schema

  def parse_list(bytes, acc) do
    %{element: element, rest: bytes} = parse_element(bytes)
    acc = [element | acc]
    if bytes == "" do
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
      1	-> :video
      2	-> :audio
      3	-> :complex
      16	-> :logo
      17	-> :subtitle
      18	-> :buttons
      32	-> :control
      33	-> :metadata
    end
  end

  def parse(bytes, :uint, _name) do
    :binary.decode_unsigned(bytes)
  end

  def parse(bytes, :integer, _name) do
    <<int::integer-signed>> = bytes
    int
  end

  def parse(bytes, :float, _name) do
    bytes
  end

  def parse(bytes, :binary, :SimpleBlock) do
    # https://tools.ietf.org/id/draft-lhomme-cellar-matroska-04.html#rfc.section.6.2.4.4

    # track_number is a vint with size 1 or 2 bytes
    %{vint: track_number_vint, rest: bytes} = Vint.parse(bytes)
    << timecode::integer-signed-size(16), flags::bitstring-size(8), data::binary>> = bytes
    <<keyframe::1, reserved::3, invisible::1, lacing::2, discardable::1>> = flags

    if reserved != 0 do
      IO.puts "SimpleBlock reserved bits in header flag should all be 0 but they are #{reserved}"
    end

    lacing = case lacing do
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
          keyframe: keyframe==1,
          reserved: reserved,
          invisible: invisible==1,
          lacing: lacing,
          discardable: discardable==1
      },
      data: data
    }
  end

  def parse(bytes, :binary, _name) do
    bytes
    # Base.encode16(bytes)
  end

  def parse(bytes, :string, :CodecID) do
    codec_string = Enum.join(for <<c::utf8 <- bytes>>, do: <<c::utf8>>)
    case codec_string do
      "A_OPUS" -> :opus
      "A_VORBIS" -> :vorbis
      "V_VP8" -> :vp8
      "V_VP9" -> :vp9
      _ -> raise "Illegal codec for a .webm file: #{codec_string}"
    end
    # Video	“V_”
    # Audio	“A_”
    # Subtitle	“S_”
    # Button	“B_”
  end

  def parse(bytes, :string, _name) do
    Enum.join(for <<c::utf8 <- bytes>>, do: <<c::utf8>>)
  end

  def parse(bytes, :utf_8, _name) do
    bytes
    |> String.codepoints()
    |> Enum.reduce("", fn(codepoint, result) ->
                     << parsed :: 8>> = codepoint
                     if parsed == 0, do: result, else: result <> <<parsed>>
                   end)
  end

  def parse(bytes, :date, _name) do
    bytes
  end

  def parse(_bytes, :void, _name) do
    nil # Base.encode16(bytes)
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

    if type == :unknown do
      IO.puts "unknown element ID: #{id}"
    end

    with %{bytes: data, rest: bytes} <- trim_bytes(bytes, data_size) do
      element = %{
        id: id,
        data_size: data_size,
        name: name,
        data: parse(data, type, name),
        type: type
      }

      %{element: element, rest: bytes}
    end
  end

  def trim_bytes(bytes, how_many) do
    <<bytes::binary-size(how_many), rest::binary>> = bytes
    %{bytes: bytes, rest: rest}
  end
end