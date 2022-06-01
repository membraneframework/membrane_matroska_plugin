defmodule Membrane.Matroska.Parser.Helper do
  @moduledoc false

  # Module for parsing a Matroska / MKV binary stream (such as from a file) used by `Membrane.Matroska.Demuxer`.

  # A Matroska file is defined as a Matroska file that contains one segment and satisfies strict constraints.
  # A Matroska file is an EBML file (Extendable-Binary-Meta-Language) satisfying certain other constraints.

  # Docs:
  #   - EBML https://www.rfc-editor.org/rfc/rfc8794.html
  #   - Matroska https://www.webmproject.org/docs/container/
  #   - Matroska https://matroska.org/technical/basics.html

  # The module extracts top level elements of the [Matroska Segment](https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#section-7)
  # and incrementally passes these parsed elements forward.
  # All top level elements other than `Cluster` occur only once and contain metadata whereas a `Cluster` element holds all the tracks'
  # encoded frames grouped by timestamp. It is RECOMMENDED that the size of each individual Cluster Element be limited to store no more than
  # 5 seconds or 5 megabytes.

  alias Membrane.Matroska.Parser.EBML

  # Main function used for parsing a file
  @spec parse(binary, function) :: {parsed :: list, unparsed :: binary}
  def parse(unparsed, schema) do
    do_parse([], unparsed, schema)
  end

  @spec parse_many!(list, binary, function) :: list
  def parse_many!(acc, bytes, schema) do
    case maybe_parse_element(bytes, schema) do
      {:ok, {element, <<>>}} ->
        [element | acc]

      {:ok, {element, rest}} ->
        parse_many!([element | acc], rest, schema)
    end
  end

  @spec do_parse(list, binary, function) :: {list, binary}
  defp do_parse(acc, bytes, schema) do
    case maybe_parse_element(bytes, schema) do
      {:error, :need_more_bytes} ->
        {acc, bytes}

      {:ok, {element, <<>>}} ->
        {[element | acc], <<>>}

      {:ok, {element, rest}} ->
        do_parse([element | acc], rest, schema)
    end
  end

  @spec maybe_parse_element(binary, function) ::
          {:error, :need_more_bytes} | {:ok, {{atom, list}, binary}}
  defp maybe_parse_element(bytes, schema) do
    with {:ok, {element_name, rest}} <- EBML.decode_element_name(bytes),
         {:ok, {_element_width, rest}} <- EBML.decode_vint(rest) do
      if schema.(element_name) == :ApplyFlatParsing do
        maybe_parse_element(rest, schema)
      else
        maybe_parse_recursively(bytes, schema)
      end
    end
  end

  @spec maybe_parse_recursively(binary, function) ::
          {:error, :need_more_bytes} | {:ok, {{atom, list}, binary}}
  defp maybe_parse_recursively(bytes, schema) do
    with {:ok, {name, data, rest}} <- EBML.decode_element(bytes) do
      parsing_function = schema.(name)

      if parsing_function == (&EBML.parse_master/2) do
        {:ok, {{name, EBML.parse_master(data, schema)}, rest}}
      else
        {:ok, {{name, parsing_function.(data)}, rest}}
      end
    end
  end
end
