defmodule Membrane.WebM.Parser.EBML do
  @moduledoc """
  Helper functions for decoding and encoding EBML elements.

  EBML RFC: https://www.rfc-editor.org/rfc/rfc8794.html
  Numbers are encoded as VINTs in EBML
  VINT - variable-length integer

  A VINT consists of three parts:
  - VINT_WIDTH - the number N of leading `0` bits in the first byte of the VINT signifies how many bytes the VINT takes up in total: N+1
    having no leading `0` bits is also allowed in which case the VINT takes up 1 byte
  - VINT_MARKER - the `1` bit immediately following the VINT_WIDTH `0` bits
  - VINT_DATA - the 7*N bits following the VINT_MARKER

  TODO: element_id is the only type of VINT for which it is illegal to take up more space than is necessary i.e.
    1 0000001 is legal
    0 1 00000000000001 is illegal because a shorter encoding of VINT_DATA is available
    (it fits in 1 byte but 2 are used)

  TODO: deal with unknown element sizes
  (these shouldn't be used but can occur only in master elements)
  EBML Element Data Size VINTs with VINT_DATA consisting of only 1's are reserver to mean `unknown` e.g.:
    1 1111111
    0 1 11111111111111
  determining where an unknonw-sized elements end is tricky
  https://www.rfc-editor.org/rfc/rfc8794.html#section-6.2
  """
  use Bitwise

  alias Membrane.WebM.Schema

  @doc "left for reference but shouldn't be used"
  def parse_vint(<<first_byte::unsigned-size(8), _rest::binary>> = bytes) do
    vint_width = get_vint_width(first_byte)
    <<vint_bytes::binary-size(vint_width), rest::binary>> = bytes
    <<vint::integer-size(vint_width)-unit(8)>> = vint_bytes
    vint_data = get_vint_data(vint, vint_width)
    element_id = Integer.to_string(vint, 16)

    %{
      vint: %{
        vint: vint,
        vint_width: vint_width,
        vint_data: vint_data,
        element_id: element_id
      },
      rest: rest
    }
  end

  @doc """
  Returns an EBML element's name, type and data
  """
  def decode_element(bytes) do
    {id, bytes} = decode_element_id(bytes)
    {data_size, bytes} = decode_vint(bytes)
    name = Schema.element_id_to_name(id)
    type = Schema.element_type(name)

    # `Segment` is a special element requiring different behaviour of the parser
    # the parser should only wait for more bytes in case of top-level children elements of `Segment`, not the `Segment` itself
    if name == :Segment do
      {:ignore_element_header, bytes}
    else
      case split_bytes(bytes, data_size) do
        {data, bytes} ->
          # TODO: remove; only for debugging
          if name == :Unknown do
            IO.warn("unknown element ID: #{id}")
          end

          {name, type, data, bytes}

        :need_more_bytes ->
          :need_more_bytes
      end
    end
  end

  defp split_bytes(bytes, how_many) do
    if how_many > byte_size(bytes) do
      :need_more_bytes
    else
      <<bytes::binary-size(how_many), rest::binary>> = bytes
      {bytes, rest}
    end
  end

  @doc """
  Returns the `EBML Element ID` of the given VINT.

  EMBL elements are identified by the hex representation of the entire leading VINT including WIDTH, MARKER and DATA
  """
  def decode_element_id(<<first_byte::unsigned-size(8), _rest::binary>> = bytes) do
    vint_width = get_vint_width(first_byte)
    <<vint_bytes::binary-size(vint_width), rest::binary>> = bytes
    <<vint::integer-size(vint_width)-unit(8)>> = vint_bytes

    {Integer.to_string(vint, 16), rest}
  end

  @doc "Returns the number encoded in the VINT_DATA field of the VINT"
  def decode_vint(<<first_byte::unsigned-size(8), _rest::binary>> = bytes) do
    vint_width = get_vint_width(first_byte)
    <<vint_bytes::binary-size(vint_width), rest::binary>> = bytes
    <<vint::integer-size(vint_width)-unit(8)>> = vint_bytes

    {get_vint_data(vint, vint_width), rest}
  end

  # the numbers are bit masks for extracting the data part of a VINT
  defp get_vint_data(vint, vint_width) do
    case vint_width do
      1 -> vint &&& 18_446_744_073_709_551_743
      2 -> vint &&& 18_446_744_073_709_567_999
      3 -> vint &&& 18_446_744_073_711_648_767
      4 -> vint &&& 18_446_744_073_977_987_071
      5 -> vint &&& 18_446_744_108_069_289_983
      6 -> vint &&& 18_446_748_471_756_062_719
      7 -> vint &&& 18_447_307_023_662_972_927
      8 -> vint &&& 18_518_801_667_747_479_551
    end
  end

  defp get_vint_width(byte) do
    cond do
      (byte &&& 0b10000000) == 0b10000000 -> 1
      (byte &&& 0b01000000) == 0b01000000 -> 2
      (byte &&& 0b00100000) == 0b00100000 -> 3
      (byte &&& 0b00010000) == 0b00010000 -> 4
      (byte &&& 0b00010000) == 0b00010000 -> 5
      (byte &&& 0b00001000) == 0b00001000 -> 6
      (byte &&& 0b00000100) == 0b00000100 -> 7
      (byte &&& 0b00000010) == 0b00000010 -> 8
      # TODO: check why this is needed (it is in fact necessary):
      (byte &&& 0b00000001) == 0b00000001 -> 8
    end
  end

  def encode_vint(number) do
    limits = [
      126,
      16382,
      2_097_150,
      268_435_454,
      34_359_738_366,
      4_398_046_511_102,
      562_949_953_421_310,
      72_057_594_037_927_936
    ]

    # TODO: does this work for determining octets?
    octets = Enum.find_index(limits, fn max_num -> number < max_num end) + 1
    width_bits = octets - 1
    data_bits = octets * 7

    <<0::size(width_bits), 1::1, number::big-size(data_bits)>>
  end

  def encode_element_id(name) do
    name |> Schema.name_to_element_id() |> Base.decode16!()
  end
end
