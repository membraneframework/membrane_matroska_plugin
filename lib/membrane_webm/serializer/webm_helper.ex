defmodule Membrane.Matroska.Serializer.Helper do
  @moduledoc false

  # Module for serializing Matroska elements into writable bytes.

  use Bitwise

  alias Membrane.Matroska.Schema

  @spec serialize({atom, any}) :: binary
  def serialize({name, data}) do
    schema = &Schema.serialize_webm/1
    serializing_function = schema.(name)

    serializing_function.(data, name, schema)
  end

  @spec serialize(list({atom, any})) :: binary
  def serialize(elements_list) when is_list(elements_list) do
    Enum.map_join(elements_list, &serialize/1)
  end
end
