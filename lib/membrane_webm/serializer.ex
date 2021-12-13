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

  # # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.2
  # def serialize(0, :uint, name) do
  #   IO.puts("serialize uint #{name}")
  #   element_id = EBML.encode_element_id(name)
  #   element_data = <<>>
  #   element_data_size = EBML.encode_vint(0)

  #   element_id <> element_data_size <> element_data
  #   <<>>
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

  # def serialize(0, :float, name) do
  #   IO.puts("serialize float #{name}")
  #   element_id = EBML.encode_element_id(name)
  #   element_data = <<>>
  #   element_data_size = EBML.encode_vint(0)

  #   element_id <> element_data_size <> element_data
  # end

  def serialize(num, :float, name) do
    IO.puts("serialize float #{name}")
    element_id = EBML.encode_element_id(name)
    element_data = <<num::float-big>>
    element_data_size = byte_size(element_data) |> EBML.encode_vint()

    element_id <> element_data_size <> element_data
  end

  # def serialize({timestamp, data}, :binary, :SimpleBlock) do
  #   IO.puts("serialize simpleblock")

  #   track_number = 1
  #   keyframe = 1
  #   reserved = 0
  #   invisible = 0
  #   lacing = 0
  #   discardable = 0

  #   EBML.encode_vint(track_number) <>
  #     <<timestamp::integer-signed-big-size(16), keyframe::1, reserved::3, invisible::1, lacing::2,
  #       discardable::1, data::binary>>
  # end

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

  # FIXME:
  def serialize(length, :void, name) do
    IO.puts("serialize #{name}")
    element_id = EBML.encode_element_id(name)
    element_data = <<0::size(length)>>
    element_data_size = byte_size(element_data) |> EBML.encode_vint()

    element_id <> element_data_size <> element_data
  end

  def serialize_opus_frame(data, timecode, track_number) do
    timecode = <<timecode::integer-signed-big-size(16)>>
    # header_field: value::number_of_bits
    # keyframe: 1::0
    # reserved: 0::3
    # invisible: 0::1
    # lacing: 0::2
    # discardable: 0::1
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
    # header_field: value::number_of_bits
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
