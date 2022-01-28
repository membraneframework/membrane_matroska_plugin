defmodule Membrane.WebM.Serializer do
  @moduledoc """
  Module for serializing WebM elements into writable bytes.

  """
  alias Membrane.WebM.Parser.{EBML, Codecs}
  alias Membrane.WebM.Schema

  use Bitwise

  # TODO: split serializer into ebml and webm specific stuff
  # TODO: make SimpleBlock a struct

  @print_blocks false
  @print_elements true

  def serialize_not(stuff) do
    inspect(stuff, limit: :infinity, pretty: true)
  end

  def serialize({name, data}) do
    type = Schema.element_type(name)
    serialize(data, type, name)
  end

  def serialize(elements_list) when is_list(elements_list) do
    elements_list
    |> Enum.map(&serialize/1)
    |> Enum.join()
  end

  defp generic_serialize(element_data, type, name) do
    if @print_elements and name != :SimpleBlock, do: IO.puts("serialize #{type} #{name}")

    element_id = EBML.encode_element_id(name)
    element_data_size = byte_size(element_data) |> EBML.encode_vint()

    element_id <> element_data_size <> element_data
  end

  # this function creates Segment as an element with unknonw width
  # TODO: elements with unknonw width currently can't be parsed
  defp serialize(elements, :master, :Segment) do
    element_id = EBML.encode_element_id(:Segment)
    element_data_size = <<0b11111111>>

    element_data =
      Enum.reduce(elements, <<>>, fn {name, data}, acc -> serialize({name, data}) <> acc end)

    element_id <> element_data_size <> element_data
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

  defp serialize(number, :integer, name) do
    int_value_ranges = [
      (-2 ** 7)..(2 ** 7 - 1),
      (-2 ** 15)..(2 ** 15 - 1),
      (-2 ** 23)..(2 ** 23 - 1),
      (-2 ** 31)..(2 ** 31 - 1),
      (-2 ** 39)..(2 ** 39 - 1),
      (-2 ** 47)..(2 ** 47 - 1),
      (-2 ** 55)..(2 ** 55 - 1),
      (-2 ** 63)..(2 ** 63 - 1)
    ]

    octets = Enum.find_index(int_value_ranges, fn range -> number in range end) + 1
    element_data = <<number::integer-signed-unit(8)-size(octets)>>
    generic_serialize(element_data, :integer, name)
  end

  defp serialize(string, :string, name) do
    generic_serialize(string, :string, name)
  end

  # FIXME: I'm not sure if this get's encoded properly
  defp serialize(string, :utf_8, name) do
    generic_serialize(string, :utf_8, name)
  end

  defp serialize(num, :float, name) do
    element_data = <<num::float-big>>

    generic_serialize(element_data, :float, name)
  end

  defp serialize(length, :void, name) do
    # FIXME: i don't see how to avoid funny business on 2^(7*n) +- 1 lengths
    # answer: create two void elements, each holding half the bytes
    n = trunc(:math.log2(length - 1) / 7) + 1
    length = (length - n - 1) * 8
    element_data = <<0::size(length)>>

    generic_serialize(element_data, :void, name)
  end

  defp serialize({timecode, data, track_number, type} = block, :binary, :SimpleBlock) do
    if @print_blocks, do: IO.puts("serialize #{type} simpleblock")

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
