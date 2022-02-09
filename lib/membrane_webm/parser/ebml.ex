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
  - VINT_DATA - the 7*N bits following the VINT_MARKER containing the unsigned integer (big-endian)

  As an example here are three ways to encode the decimal number `13`:
  ```
  1 0001101
  0 1 000000 00001101
  00 1 00000 00000000 00001101
  ```

  An EBML_ELEMENT consists of three consecutive parts:
  - ELEMENT_ID - a VINT defined in a schema which specifies the corresponding EBML_TYPE and other constraints
  - ELEMENT_DATA_SIZE - a VINT of how many bytes the ELEMENT_DATA field occupies
  - ELEMENT_DATA - the actual payload of the element, interpreted differently for each EBML_TYPE

  Possible EBML_TYPE values:
  - Signed Integer
  - Unsigned Integer
  - Float
  - String
  - UTF-8
  - Date
  - Master

  Only Master Elements can contain other Elements in their ELEMENT_DATA which occur one after the other simply concatenated.

  Note that this module does not support parsing Master Elements with unknown data size
  https://www.rfc-editor.org/rfc/rfc8794.html#section-6.2
  """
  use Bitwise

  alias Membrane.WebM.Schema
  alias Membrane.Time

  @type t :: :integer | :uint | :float | :string | :utf8 | :date | :master | :binary

  # left for reference but shouldn't be used. unsafe - doesn't check if first byte or `vint_width` + 1 bytes are available
  # def parse_vint!(<<first_byte::unsigned-size(8), _rest::binary>> = bytes) do
  #   vint_width = get_vint_width(first_byte)
  #   <<vint_bytes::binary-size(vint_width), rest::binary>> = bytes
  #   <<vint::integer-size(vint_width)-unit(8)>> = vint_bytes
  #   vint_data = get_vint_data(vint, vint_width)
  #   element_id = Integer.to_string(vint, 16)

  #   %{
  #     vint: %{
  #       vint: vint,
  #       vint_width: vint_width,
  #       vint_data: vint_data,
  #       element_id: element_id
  #     },
  #     rest: rest
  #   }
  # end

  @doc """
  Discards `element_id`, `element_data_size` and returns the available portion of `element_data`.
  """
  @spec consume_element_header(binary) :: {:ok, binary} | {:error, :need_more_bytes}
  def consume_element_header(bytes) do
    with {:ok, {_id, bytes}} <- decode_element_id(bytes) do
      case bytes do
        <<first_byte::unsigned-size(8), _rest::binary>> ->
          vint_width = get_vint_width(first_byte)

          case bytes do
            <<_vint_bytes::binary-size(vint_width), rest::binary>> ->
              {:ok, rest}

            _too_short ->
              {:error, :need_more_bytes}
          end

        _too_short ->
          {:error, :need_more_bytes}
      end
    end
  end

  @doc """
  Returns an EBML element's name, type, and data
  """
  @spec decode_element(binary) ::
          {:ok, {name :: atom, data :: binary, rest :: binary}}
          | {:error, :need_more_bytes}
  def decode_element(bytes) do
    with {:ok, {id, bytes}} <- decode_element_id(bytes),
         {:ok, {data_size, bytes}} <- decode_vint(bytes) do
      name = Schema.element_id_to_name(id)

      with {:ok, {data, rest}} <- split_bytes(bytes, data_size) do
        # TODO: remove; only for debugging
        if name == :Unknown do
          IO.warn("Unknown element ID: #{id}")
        end

        {:ok, {name, data, rest}}
      end
    end
  end

  @doc """
  Returns the EBML ELEMENT_ID of the first Element in the input binary.

  EMBL elements are identified by the hexadecimal representation of the entire leading VINT including WIDTH, MARKER and DATA
  """
  @spec decode_element_id(binary) :: {:ok, {integer, binary}} | {:error, :need_more_bytes}
  def decode_element_id(<<first_byte::unsigned-size(8), _rest::binary>> = element) do
    vint_width = get_vint_width(first_byte)

    case element do
      <<vint_bytes::binary-size(vint_width), rest::binary>> ->
        <<vint::integer-size(vint_width)-unit(8)>> = vint_bytes
        {:ok, {vint, rest}}

      _too_short ->
        {:error, :need_more_bytes}
    end
  end

  def decode_element_id(_too_short) do
    {:error, :need_more_bytes}
  end

  @doc "Returns the number encoded in the VINT_DATA field of the first VINT in the input binary"
  @spec decode_vint(binary) :: {:ok, {non_neg_integer, binary}} | {:error, :need_more_bytes}
  def decode_vint(<<first_byte::unsigned-size(8), _rest::binary>> = bytes) do
    vint_width = get_vint_width(first_byte)

    case bytes do
      <<vint_bytes::binary-size(vint_width), rest::binary>> ->
        <<vint::integer-size(vint_width)-unit(8)>> = vint_bytes
        {:ok, {get_vint_data(vint, vint_width), rest}}

      _too_short ->
        {:error, :need_more_bytes}
    end
  end

  def decode_vint(_too_short) do
    {:error, :need_more_bytes}
  end

  defp split_bytes(bytes, how_many) do
    if how_many > byte_size(bytes) do
      {:error, :need_more_bytes}
    else
      <<bytes::binary-size(how_many), rest::binary>> = bytes
      {:ok, {bytes, rest}}
    end
  end

  # See https://datatracker.ietf.org/doc/html/rfc8794#section-4.1
  defp get_vint_width(byte) do
    cond do
      (byte &&& 0b10000000) > 0 -> 1
      (byte &&& 0b01000000) > 0 -> 2
      (byte &&& 0b00100000) > 0 -> 3
      (byte &&& 0b00010000) > 0 -> 4
      (byte &&& 0b00001000) > 0 -> 5
      (byte &&& 0b00000100) > 0 -> 6
      (byte &&& 0b00000010) > 0 -> 7
      (byte &&& 0b00000001) > 0 -> 8
    end
  end

  # See https://datatracker.ietf.org/doc/html/rfc8794#section-4.3
  defp get_vint_data(vint, vint_width) do
    case vint_width do
      1 -> vint &&& 0x1000000000000007F
      2 -> vint &&& 0x10000000000003FFF
      3 -> vint &&& 0x100000000001FFFFF
      4 -> vint &&& 0x1000000000FFFFFFF
      5 -> vint &&& 0x100000007FFFFFFFF
      6 -> vint &&& 0x1000003FFFFFFFFFF
      7 -> vint &&& 0x10001FFFFFFFFFFFF
      8 -> vint &&& 0x100FFFFFFFFFFFFFF
    end
  end

  @doc "
  Encodes the provided number as a VINT ready for serialization

  See https://datatracker.ietf.org/doc/html/rfc8794#section-4
  "
  @spec encode_vint(non_neg_integer) :: binary
  def encode_vint(number) do
    # +==============+======================+
    # | Octet Length | Possible Value Range |
    # +==============+======================+
    # | 1            | 0 to 2^(7) - 2       |
    # +--------------+----------------------+
    # | 2            | 0 to 2^(14) - 2      |
    # +--------------+----------------------+
    # | 3            | 0 to 2^(21) - 2      |
    # +--------------+----------------------+
    # | 4            | 0 to 2^(28) - 2      |
    # +--------------+----------------------+
    # | 5            | 0 to 2^(35) - 2      |
    # +--------------+----------------------+
    # | 6            | 0 to 2^(42) - 2      |
    # +--------------+----------------------+
    # | 7            | 0 to 2^(49) - 2      |
    # +--------------+----------------------+
    # | 8            | 0 to 2^(56) - 2      |
    # +--------------+----------------------+

    limits = [
      126,
      16_382,
      2_097_150,
      268_435_454,
      34_359_738_366,
      4_398_046_511_102,
      562_949_953_421_310,
      72_057_594_037_927_936
    ]

    octets = Enum.find_index(limits, fn max_num -> number < max_num end) + 1
    width_bits = octets - 1
    data_bits = octets * 7

    <<0::size(width_bits), 1::1, number::big-size(data_bits)>>
  end

  @doc "
  Returns the Element's ELEMENT_ID ready for serialization

  See https://datatracker.ietf.org/doc/html/rfc8794#section-5
  Matroska elements and id's https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#name-matroska-schema
  WebM supported Matroska elements https://www.webmproject.org/docs/container/#EBML
  "
  @spec encode_element_id(atom) :: binary
  def encode_element_id(name) do
    id = Schema.name_to_element_id(name)
    :binary.encode_unsigned(id, :big)
  end

  @spec parse(binary, __MODULE__.t()) :: any
  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.1
  def parse(<<>>, :integer) do
    0
  end

  def parse(bytes, :integer) do
    s = bit_size(bytes)
    <<num::signed-big-integer-size(s)>> = bytes
    num
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.2
  def parse(<<>>, :uint) do
    0
  end

  def parse(bytes, :uint) do
    :binary.decode_unsigned(bytes, :big)
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.3
  def parse(<<>>, :float) do
    0
  end

  def parse(<<num::float-big>>, :float) do
    num
  end

  def parse(bytes, :string) do
    chars = for <<c::utf8 <- bytes>>, do: <<c::utf8>>
    chars |> Enum.take_while(fn c -> c != <<0>> end) |> Enum.join()
  end

  def parse(bytes, :utf_8) do
    bytes
    |> String.codepoints()
    |> Enum.reduce("", fn codepoint, result ->
      <<parsed::8>> = codepoint
      if parsed == 0, do: result, else: result <> <<parsed>>
    end)
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.6
  def parse(<<>>, :date) do
    {{2001, 1, 1}, {0, 0, 0}}
  end

  def parse(<<nanoseconds::big-signed>>, :date) do
    seconds_zero = :calendar.datetime_to_gregorian_seconds({{2001, 1, 1}, {0, 0, 0}})
    seconds = div(nanoseconds, Time.nanosecond()) + seconds_zero
    :calendar.gregorian_seconds_to_datetime(seconds)
  end

  def parse(bytes, :binary) do
    bytes
  end

  def parse(bytes, :void) do
    bytes
  end

  def parse(bytes, :master) do
    if byte_size(bytes) == 0 do
      []
    else
      Membrane.WebM.Parser.Helper.parse_many!([], bytes)
    end
  end
end
