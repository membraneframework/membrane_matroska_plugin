defmodule Membrane.WebM.Parser.Helper do
  @moduledoc """
  Module for parsing a WebM binary stream (such as from a file) used by `Membrane.WebM.Demuxer`.

  A WebM file is defined as a Matroska file that contains one segment and satisfies strict constraints.
  A Matroska file is an EBML file (Extendable-Binary-Meta-Language) satisfying certain other constraints.

  Docs:
    - EBML https://www.rfc-editor.org/rfc/rfc8794.html
    - WebM https://www.webmproject.org/docs/container/
    - Matroska https://matroska.org/technical/basics.html

  The module extracts top level elements of the [WebM Segment](https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#section-7)
  and incrementally passes these parsed elements forward.
  All top level elements other than `Cluster` occur only once and contain metadata whereas a `Cluster` element holds all the tracks'
  encoded frames grouped by timestamp. It is RECOMMENDED that the size of each individual Cluster Element be limited to store no more than
  5 seconds or 5 megabytes.

  """
  alias Membrane.WebM.Parser.EBML
  alias Membrane.WebM.Parser.WebM

  @parser &WebM.parse/2

  @doc """
  Main function used for parsing a WebM file

  The parser needs to know if the EBML element and the Segment element header have already been parsed - called `header_parsed`

  The function expects as input bytes to be parsed and `header_parsed` (initially false)
  It returns a list of parsed top-level elements, the rest unparsed bytes and a modified `header_parsed`
  """
  @spec parse(binary, boolean) :: {list, binary, boolean}
  def parse(unparsed, false = _header_parsed) do
    case maybe_consume_webm_header(unparsed) do
      {:ok, rest} ->
        {parsed, unparsed} = parse_many([], rest)
        {parsed, unparsed, true}

      {:error, :need_more_bytes} ->
        {[], unparsed, false}
    end
  end

  def parse(unparsed, true = _header_parsed) do
    {parsed, unparsed} = parse_many([], unparsed)
    {parsed, unparsed, true}
  end

  @spec parse_many!(list, binary) :: list
  def parse_many!(acc, bytes) do
    case maybe_parse_element(bytes) do
      {:ok, {element, <<>>}} ->
        [element | acc]

      {:ok, {element, rest}} ->
        parse_many!([element | acc], rest)
    end
  end

  @spec maybe_consume_webm_header(binary) :: {:ok, binary} | {:error, :need_more_bytes}
  defp maybe_consume_webm_header(bytes) do
    # consume the EBML element
    with {:ok, {_ebml, rest}} <- maybe_parse_element(bytes) do
      # consume Segment's element_id and element_data_size, return only element_data
      EBML.consume_element_header(rest)
    end
  end

  @spec parse_many(list, binary) :: {list, binary}
  defp parse_many(acc, bytes) do
    case maybe_parse_element(bytes) do
      {:error, :need_more_bytes} ->
        {acc, bytes}

      {:ok, {element, <<>>}} ->
        {[element | acc], <<>>}

      {:ok, {element, rest}} ->
        parse_many([element | acc], rest)
    end
  end

  @spec maybe_parse_element(binary) :: {:error, :need_more_bytes} | {:ok, {{atom, any}, binary}}
  defp maybe_parse_element(bytes) do
    with {:ok, {name, data, rest}} <- EBML.decode_element(bytes) do
      element = {name, @parser.(data, name)}
      {:ok, {element, rest}}
    end
  end
end
