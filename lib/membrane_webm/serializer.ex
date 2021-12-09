defmodule Membrane.WebM.Serializer do
  @moduledoc """
  Module for serializing WebM elements into writable bytes.

  """
  alias Membrane.WebM.Parser.EBML
  alias Membrane.WebM.Schema

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

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.2
  def serialize(0, :uint, name) do
    IO.puts("serialize uint #{name}")
    <<>>
  end

  def serialize(uint, :uint, name) do
    IO.puts("serialize uint #{name}")
    element_id = EBML.encode_element_id(name)
    element_data = EBML.encode_vint(uint)
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

  def serialize(0, :float, name) do
    IO.puts("serialize float #{name}")
    element_id = EBML.encode_element_id(name)
    element_data = <<>>
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

  # #FIXME:delete

  # defp parse(bytes, :binary, :SimpleBlock) do
  #   # track_number is a vint with size 1 or 2 bytes
  #   {track_number, body} = EBML.decode_vint(bytes)

  #   <<timecode::integer-signed-big-size(16), keyframe::1, reserved::3, invisible::1, lacing::2,
  #     discardable::1, data::binary>> = body

  #   lacing =
  #     case lacing do
  #       0b00 -> :no_lacing
  #       0b01 -> :Xiph_lacing
  #       0b11 -> :EBML_lacing
  #       0b10 -> :fixed_size_lacing
  #     end

  #   %{
  #     track_number: track_number,
  #     timecode: timecode,
  #     header_flags: %{
  #       keyframe: keyframe == 1,
  #       reserved: reserved,
  #       invisible: invisible == 1,
  #       lacing: lacing,
  #       discardable: discardable == 1
  #     },
  #     data: data
  #   }
  # end

  # #FIXME:delete

  def serialize({timestamp, data}, :binary, :SimpleBlock) do
    IO.puts("serialize simpleblock")

    track_number = 1
    keyframe = 1
    reserved = 0
    invisible = 0
    lacing = 0
    discardable = 0

    EBML.encode_vint(track_number) <>
      <<timestamp::integer-signed-big-size(16), keyframe::1, reserved::3, invisible::1, lacing::2,
        discardable::1, data::binary>>
  end

  def serialize(bytes, :binary, name) do
    IO.puts("serialize binary #{name}")
    element_id = EBML.encode_element_id(name)
    element_data = bytes
    element_data_size = byte_size(element_data) |> EBML.encode_vint()

    element_id <> element_data_size <> element_data
  end
end
