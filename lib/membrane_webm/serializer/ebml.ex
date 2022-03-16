defmodule Membrane.WebM.Serializer.EBML do
  @moduledoc false

  alias Membrane.WebM.Schema

  @int_value_ranges [
    (-2 ** 7)..(2 ** 7 - 1),
    (-2 ** 15)..(2 ** 15 - 1),
    (-2 ** 23)..(2 ** 23 - 1),
    (-2 ** 31)..(2 ** 31 - 1),
    (-2 ** 39)..(2 ** 39 - 1),
    (-2 ** 47)..(2 ** 47 - 1),
    (-2 ** 55)..(2 ** 55 - 1),
    (-2 ** 63)..(2 ** 63 - 1)
  ]

  @vint_value_limits [
    126,
    16_382,
    2_097_150,
    268_435_454,
    34_359_738_366,
    4_398_046_511_102,
    562_949_953_421_310,
    72_057_594_037_927_936
  ]

  @spec serialize_master(list, atom, function) :: binary
  def serialize_master(child_elements, name, schema) do
    Enum.reduce(child_elements, <<>>, fn {name, data}, acc ->
      serializing_function = schema.(name)
      serializing_function.(data, name, schema) <> acc
    end)
    |> serialize_element(name, schema)
  end

  @spec serialize_uint(non_neg_integer, atom, function) :: binary
  def serialize_uint(number, name, schema) do
    :binary.encode_unsigned(number, :big)
    |> serialize_element(name, schema)
  end

  @spec serialize_date(non_neg_integer, atom, function) :: binary
  def serialize_date(date, name, schema) do
    :binary.encode_unsigned(date, :big)
    |> serialize_element(name, schema)
  end

  @spec serialize_integer(integer, atom, function) :: binary
  def serialize_integer(number, name, schema) do
    octets = Enum.find_index(@int_value_ranges, fn range -> number in range end) + 1

    <<number::integer-signed-unit(8)-size(octets)>>
    |> serialize_element(name, schema)
  end

  @spec serialize_string(binary, atom, function) :: binary
  def serialize_string(string, name, schema) do
    string
    |> serialize_element(name, schema)
  end

  @spec serialize_utf8(binary, atom, function) :: binary
  def serialize_utf8(string, name, schema) do
    string
    |> serialize_element(name, schema)
  end

  @spec serialize_float(float, atom, function) :: binary
  def serialize_float(number, name, schema) do
    <<number::float-big>>
    |> serialize_element(name, schema)
  end

  @spec serialize_binary(binary, atom, function) :: binary
  def serialize_binary(bytes, name, schema) do
    bytes
    |> serialize_element(name, schema)
  end

  @spec serialize_element(binary, atom, function) :: binary
  def serialize_element(element_data, element_name, _schema) do
    element_id = encode_element_id(element_name)
    element_data_size = byte_size(element_data) |> encode_vint()

    element_id <> element_data_size <> element_data
  end

  # Encodes the provided number as a VINT ready for serialization
  # See https://datatracker.ietf.org/doc/html/rfc8794#section-4
  @spec encode_vint(non_neg_integer) :: binary
  def encode_vint(number) do
    octets = Enum.find_index(@vint_value_limits, fn max_num -> number < max_num end) + 1
    width_bits = octets - 1
    data_bits = octets * 7

    <<0::size(width_bits), 1::1, number::big-size(data_bits)>>
  end

  # Returns the Element's ELEMENT_ID ready for serialization
  # See https://datatracker.ietf.org/doc/html/rfc8794#section-5
  @spec encode_element_id(atom) :: binary
  def encode_element_id(name) do
    id = Schema.name_to_element_id(name)
    :binary.encode_unsigned(id, :big)
  end
end
