defmodule Membrane.WebM.Serializer do
  @moduledoc """
  Module for serializing WebM elements into writable bytes.

  """
  alias Membrane.WebM.Parser.EBML
  alias Membrane.WebM.Schema

  def serialize({name, data}) do
    IO.puts("serialize #{name}")
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
end
