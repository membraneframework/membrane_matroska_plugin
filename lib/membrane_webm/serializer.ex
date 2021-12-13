defmodule Membrane.WebM.Serializer do
  @moduledoc """
  Module for serializing WebM elements into writable bytes.

  """
  alias Membrane.WebM.Parser.EBML
  alias Membrane.WebM.Schema

  use Bitwise

  def serialize({name, data}) do
    # IO.puts("serialize #{name}")
    type = Schema.element_type(name)
    serialize(data, type, name)
  end

  def serialize_many(elements) do
    Enum.reduce(elements, <<>>, fn {name, data}, acc -> serialize({name, data}) <> acc end)
  end

  def serialize(data, :master, :Segment) do
    IO.puts("serialize master Segment")
    element_id = EBML.encode_element_id(:Segment)
    element_data = serialize_many(data)
    element_data_size = byte_size(element_data) |> EBML.encode_max_width_vint()

    IO.inspect(element_id <> element_data_size <> element_data)
  end

  def serialize(data, :master, name) do
    IO.puts("serialize master #{name}")
    element_id = EBML.encode_element_id(name)
    element_data = serialize_many(data)
    element_data_size = byte_size(element_data) |> EBML.encode_vint()

    IO.inspect(element_id <> element_data_size <> element_data)
  end

  # def serialize(uint, :uint, :TrackType) do
  #   IO.puts("serialize uint TrackType")
  #   element_id = EBML.encode_element_id(:TrackType)
  #   element_data = :binary.encode_unsigned(uint, :big)
  #   element_data_size = byte_size(element_data) |> EBML.encode_vint()

  #   element_id <> element_data_size <> element_data
  # end

  def serialize(uint, :uint, name) do
    IO.puts("serialize uint #{name}")
    element_id = EBML.encode_element_id(name)
    element_data = :binary.encode_unsigned(uint, :big)
    element_data_size = byte_size(element_data) |> EBML.encode_vint()

    element_id <> element_data_size <> element_data
  end

  def serialize(string, :string, name) do
    IO.puts("serialize string #{name}")
    element_id = EBML.encode_element_id(name)
    element_data = string
    element_data_size = byte_size(element_data) |> EBML.encode_vint()

    element_id <> element_data_size <> element_data
  end

  def serialize(string, :utf_8, name) do
    IO.puts("serialize string #{name}")
    element_id = EBML.encode_element_id(name)
    element_data = string
    element_data_size = byte_size(element_data) |> EBML.encode_vint()

    element_id <> element_data_size <> element_data
  end

  def serialize(num, :float, name) do
    IO.puts("serialize float #{name}")
    element_id = EBML.encode_element_id(name)
    element_data = <<num::float-big>>
    element_data_size = byte_size(element_data) |> EBML.encode_vint()

    element_id <> element_data_size <> element_data
  end

  # FIXME:
  def serialize({timecode, data, track_number, type}, :binary, :SimpleBlock) do
    # IO.puts("serialize simpleblock")

    cond do
      type == :opus ->
        serialize_opus_frame(data, timecode, track_number)

      type == :vp8 or type == :vp9 ->
        serialize_vpx_frame(data, timecode, track_number)
    end
  end

  def serialize(bytes, :binary, name) do
    IO.puts("serialize binary #{name}")
    element_id = EBML.encode_element_id(name)
    element_data = bytes
    element_data_size = byte_size(element_data) |> EBML.encode_vint()

    element_id <> element_data_size <> element_data
  end

  def serialize(length, :void, name) do
    # FIXME: i don't see how to avoid funny business on 2^(7*n) +- 1 lengths
    n = trunc(:math.log2(length - 1) / 7) + 1
    length = (length - n - 1) * 8
    IO.puts("serialize #{name}")
    element_id = EBML.encode_element_id(name)
    element_data = <<0::size(length)>>
    element_data_size = byte_size(element_data) |> EBML.encode_vint()

    result = element_id <> element_data_size <> element_data

    IO.inspect(byte_size(result))

    result
  end

  def serialize_opus_frame(data, timecode, track_number) do
    timecode = <<timecode::integer-signed-big-size(16)>>

    # flags
    #          value::number_of_bits
    # keyframe:    1::0     # always 1    - no mention of keyframes in Opus RFC
    # reserved:    0::3     # always 000  - per Matroska RFC
    # invisible:   0::1     # always 0    - assumed
    # lacing:      0::2     # always 00   - no mention in Opus RFC
    # discardable: 0::1     # always 0    - assumed
    header_flags = <<0b1000000>>

    element_id = EBML.encode_element_id(:SimpleBlock)
    element_data = EBML.encode_vint(track_number) <> timecode <> header_flags <> data
    element_data_size = byte_size(element_data) |> EBML.encode_vint()

    element_id <> element_data_size <> element_data
  end

  def serialize_vpx_frame(
        <<first_byte::unsigned-size(8), _rest::binary>> = data,
        timecode,
        track_number
      ) do
    timecode = <<timecode::integer-signed-big-size(16)>>
    keyframe = 0b1000000 &&& first_byte
    _reserved = 0b01110000 &&& first_byte
    invisible = 0b00001000 &&& first_byte
    header_flags = <<keyframe ||| invisible>>

    element_id = EBML.encode_element_id(:SimpleBlock)
    element_data = EBML.encode_vint(track_number) <> timecode <> header_flags <> data
    element_data_size = byte_size(element_data) |> EBML.encode_vint()

    element_id <> element_data_size <> element_data
  end
end
