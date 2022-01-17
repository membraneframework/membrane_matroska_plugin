defmodule Membrane.WebM.Parser.WebM do
  @moduledoc """
  Module for parsing a WebM binary stream (such as from a files) used by `Membrane.WebM.Demuxer`.

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


  An EBML element consists of
  - element_id - the hexadecimal representation of a VINT i.e. "1A45DFA3"
  - element_data_size - a VINT
  - element_data - occupying as many bytes as element_data_size specifies

  The different types of elements are:
    - signed integer
    - unsigned integer
    - float
    - string
    - UTF-8
    - date
    - binary
      contents should not be interpreted by parser
    - master
      The Master Element contains zero or more other elements. Any data
      contained within a Master Element that is not part of a Child Element MUST be ignored.
  """
  alias Membrane.WebM.Parser.EBML
  alias Membrane.WebM.Parser.Matroska

  # take unparsed bytes and info if header is consumed and attempt to parse it
  def process(unparsed, False) do
    case consume_webm_header(unparsed) do
      {:ok, rest} ->
        {parsed, unparsed} = parse_many([], rest)
        {parsed, unparsed, True}

      {:error, :need_more_bytes} ->
        {[], unparsed, False}
    end
  end

  def process(unparsed, True) do
    {parsed, unparsed} = parse_many([], unparsed)
    {parsed, unparsed, True}
  end

  def consume_webm_header(bytes) do
    # consume the EBML header
    with {:ok, {_ebml, rest}} <- parse_element(bytes) do
      # consume Segment's element_id and element_data_size, return only element_data
      EBML.consume_element_header(rest)
    end
  end

  def parse_many(acc, bytes) do
    case parse_element(bytes) do
      {:error, :need_more_bytes} ->
        {acc, bytes}

      {:ok, {element, <<>>}} ->
        {[element | acc], <<>>}

      {:ok, {element, rest}} ->
        parse_many([element | acc], rest)
    end
  end

  def parse_many!(acc, bytes) do
    case parse_element(bytes) do
      {:ok, {element, <<>>}} ->
        [element | acc]

      {:ok, {element, rest}} ->
        parse_many!([element | acc], rest)
    end
  end

  def parse_element(bytes) do
    with {:ok, {name, type, data, rest}} <- EBML.decode_element(bytes) do
      element = {name, Matroska.parse(data, type, name)}
      {:ok, {element, rest}}
    end
  end
end
