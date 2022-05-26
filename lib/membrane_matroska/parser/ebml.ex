defmodule Membrane.Matroska.Parser.EBML do
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

  alias Membrane.Matroska.Schema
  alias Membrane.Time

  @type t :: :integer | :uint | :float | :string | :utf_8 | :date | :master | :binary

  # https://datatracker.ietf.org/doc/html/rfc8794#section-7.6
  @date_zero {{2001, 1, 1}, {0, 0, 0}}

  @doc """
  Returns an EBML element's name, type, and data
  """
  @spec decode_element(binary) ::
          {:ok, {name :: atom, data :: binary, rest :: binary}}
          | {:error, :need_more_bytes}
  def decode_element(bytes) do
    with {:ok, {name, bytes}} <- decode_element_name(bytes),
         {:ok, {data_size, bytes}} <- decode_vint(bytes),
         {:ok, {data, rest}} <- split_bytes(bytes, data_size) do
      {:ok, {name, data, rest}}
    end
  end

  @doc """
  Returns the name associated with the EBML ELEMENT_ID of the first Element in the input binary.

  EMBL elements are identified by the hexadecimal representation of the entire leading VINT including WIDTH, MARKER and DATA
  """
  @spec decode_element_name(binary) :: {:ok, {atom, binary}} | {:error, :need_more_bytes}
  def decode_element_name(<<first_byte::unsigned-size(8), _rest::binary>> = element) do
    vint_width = get_vint_width(first_byte)

    case element do
      <<vint_bytes::binary-size(vint_width), rest::binary>> ->
        <<vint::integer-size(vint_width)-unit(8)>> = vint_bytes
        {:ok, {Schema.element_id_to_name(vint), rest}}

      _too_short ->
        {:error, :need_more_bytes}
    end
  end

  def decode_element_name(_too_short) do
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

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.1
  @spec parse_integer(binary) :: integer
  def parse_integer(<<>>) do
    0
  end

  def parse_integer(bytes) do
    s = bit_size(bytes)
    <<num::signed-big-integer-size(s)>> = bytes
    num
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.2
  @spec parse_uint(binary) :: non_neg_integer
  def parse_uint(<<>>) do
    0
  end

  def parse_uint(bytes) do
    :binary.decode_unsigned(bytes, :big)
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.3
  @spec parse_float(binary) :: float
  def parse_float(<<>>) do
    0
  end

  def parse_float(<<num::float-big>>) do
    num
  end

  @spec parse_string(binary) :: binary
  def parse_string(bytes) do
    chars = for <<c::utf8 <- bytes>>, do: <<c::utf8>>
    chars |> Enum.take_while(fn c -> c != <<0>> end) |> Enum.join()
  end

  @spec parse_utf8(binary) :: binary
  def parse_utf8(bytes) do
    bytes
    |> String.codepoints()
    |> Enum.reduce("", fn codepoint, result ->
      <<parsed::8>> = codepoint
      if parsed == 0, do: result, else: result <> <<parsed>>
    end)
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.6
  @spec parse_date(binary) :: :calendar.datetime()
  def parse_date(<<>>) do
    @date_zero
  end

  def parse_date(<<nanoseconds::big-signed>>) do
    seconds_zero = :calendar.datetime_to_gregorian_seconds(@date_zero)
    seconds = div(nanoseconds, Time.nanosecond()) + seconds_zero
    :calendar.gregorian_seconds_to_datetime(seconds)
  end

  @spec parse_binary(binary) :: binary
  def parse_binary(bytes) do
    bytes
  end

  @spec parse_master(binary, function) :: list
  def parse_master(bytes, schema) do
    if byte_size(bytes) == 0 do
      []
    else
      Membrane.Matroska.Parser.Helper.parse_many!([], bytes, schema)
    end
  end
end
