defmodule Membrane.WebM.Serializer do
  @moduledoc false

  # Module for serializing WebM elements into writable bytes.

  # TODO: split serializer into ebml and webm specific

  use Bitwise

  alias Membrane.WebM.Parser.Codecs
  alias Membrane.WebM.Serializer.EBML
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

  @spec serialize({atom, any}) :: binary
  def serialize({name, data}) do
    type = Schema.element_type(name)
    serialize(data, type, name)
  end

  @spec serialize(list({atom, any})) :: binary
  def serialize(elements_list) do
    Enum.map_join(elements_list, fn {name, data} ->
      serialize(data, Schema.element_type(name), name)
    end)
  end

  defp generic_serialize(element_data, _type, name) do
    element_id = EBML.encode_element_id(name)
    element_data_size = byte_size(element_data) |> EBML.encode_vint()

    element_id <> element_data_size <> element_data
  end

  @spec serialize_segment_header() :: binary
  def serialize_segment_header() do
    element_id = EBML.encode_element_id(:Segment)
    element_data_size = <<0b11111111>>
    element_id <> element_data_size
  end

  # this function creates Segment as an element with unknown width
  # note that elements with unknown width other than Segment currently can't be parsed
  defp serialize(elements, :master, :Segment) do
    element_id = EBML.encode_element_id(:Segment)
    element_data_size = <<0b11111111>>

    element_data =
      Enum.reduce(elements, <<>>, fn {name, data}, acc -> serialize({name, data}) <> acc end)

    element_id <> element_data_size <> element_data
  end

  defp serialize(contents, :master, :Cluster) do
    element_id = EBML.encode_element_id(:Cluster)
    element_data_size = byte_size(contents) |> EBML.encode_vint()

    element_id <> element_data_size <> contents
  end

  defp serialize(elements, :master, name) do
    element_data =
      Enum.reduce(elements, <<>>, fn {name, data}, acc -> serialize({name, data}) <> acc end)

    generic_serialize(element_data, :master, name)
  end

  defp serialize(uint, :uint, name) do
    element_data = :binary.encode_unsigned(uint, :big)

    generic_serialize(element_data, :uint, name)
  end

  defp serialize(date, :date, name) do
    element_data = :binary.encode_unsigned(date, :big)

    generic_serialize(element_data, :date, name)
  end

  defp serialize(number, :integer, name) do
    octets = Enum.find_index(@int_value_ranges, fn range -> number in range end) + 1
    element_data = <<number::integer-signed-unit(8)-size(octets)>>
    generic_serialize(element_data, :integer, name)
  end

  defp serialize(string, :string, name) do
    generic_serialize(string, :string, name)
  end

  defp serialize(string, :utf_8, name) do
    generic_serialize(string, :utf_8, name)
  end

  defp serialize(num, :float, name) do
    element_data = <<num::float-big>>

    generic_serialize(element_data, :float, name)
  end

  defp serialize(length, :binary, :Void) do
    # it's impossible to create void elements with size 2^(7*n) +- 1 because element_width is a vint which takes up n bytes
    # solution: create two void elements, each holding half the bytes (but not exactly half or you have the same problem)
    n = trunc(:math.log2(length - 1) / 7) + 1
    length = (length - n - 1) * 8
    element_data = <<0::size(length)>>

    generic_serialize(element_data, :binary, :Void)
  end

  defp serialize({timecode, data, track_number, _type} = block, :binary, :SimpleBlock) do
    # Opus flags
    #        value :: number_of_bits
    # keyframe:    1::0     # always 1    - no mention of keyframes in Opus RFC
    # reserved:    0::3     # always 000  - per Matroska RFC
    # invisible:   0::1     # always 0    - assumed
    # lacing:      0::2     # always 00   - no mention in Opus RFC
    # discardable: 0::1     # always 0    - assumed
    # Not sure about VP8/VP9
    timecode = <<timecode::integer-signed-big-size(16)>>
    keyframe = Codecs.keyframe_bit(block)
    header_flags = <<keyframe::1, 0::7>>

    element_data = EBML.encode_vint(track_number) <> timecode <> header_flags <> data

    generic_serialize(element_data, :master, :SimpleBlock)
  end

  defp serialize(bytes, :binary, name) do
    generic_serialize(bytes, :binary, name)
  end
end
