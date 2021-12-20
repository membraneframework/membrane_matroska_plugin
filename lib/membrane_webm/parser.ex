defmodule Membrane.WebM.Parser do
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
  use Membrane.Filter

  alias Membrane.{Buffer, Time}
  alias Membrane.WebM.Parser.EBML

  def_input_pad :input,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers,
    caps: :any

  def_output_pad :output,
    availability: :always,
    mode: :pull,
    caps: :any

  @top_level_elements [
    :EBML,
    :SeekHead,
    :Info,
    :Tracks,
    :Tags,
    :Cues,
    :Cluster
  ]

  @impl true
  def handle_init(_) do
    {:ok, %{acc: <<>>}}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _context, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload}, _context, %{acc: acc}) do
    unparsed = acc <> payload

    #FIXME: should call parse again if has enough data to parse next element
    case parse_many(unparsed, []) do
      {:return, {name, data}, rest} ->
        {{:ok,
          buffer: {:output, %Buffer{payload: data, metadata: %{webm: %{element_name: name}}}}},
         %{acc: rest}}

      :need_more_bytes ->
        {{:ok, redemand: :output}, %{acc: unparsed}}
    end
  end

  defp parse_many(bytes, acc) do
    case parse_element(bytes) do
      {{name, _data} = element, rest} when name in @top_level_elements ->
        {:return, element, rest}

      {:return, element, rest} ->
        {:return, element, rest}

      {element, <<>>} ->
        [element | acc]

      {element, rest} ->
        parse_many(rest, [element | acc])

      :need_more_bytes ->
        :need_more_bytes
    end
  end

  defp parse_element(bytes) do
    case EBML.decode_element(bytes) do
      {:ignore_element_header, element_data} ->
        parse_many(element_data, [])

      {name, type, data, rest} ->
        element = {name, parse(data, type, name)}
        {element, rest}

      :need_more_bytes ->
        :need_more_bytes
    end
  end

  defp parse(bytes, :master, _name) do
    if byte_size(bytes) == 0 do
      []
    else
      parse_many(bytes, [])
    end
  end

  defp parse(<<type::unsigned-integer-size(8)>>, :uint, :TrackType) do
    case type do
      1 -> :video
      2 -> :audio
      3 -> :complex
      16 -> :logo
      17 -> :subtitle
      18 -> :buttons
      32 -> :control
      33 -> :metadata
    end
  end

  defp parse(<<type::unsigned-integer-size(8)>>, :uint, :FlagInterlaced) do
    case type do
      # Unknown status.This value SHOULD be avoided.
      0 -> :undetermined
      # Interlaced frames.
      1 -> :interlaced
      # No interlacing.
      2 -> :progressive
    end
  end

  defp parse(<<type::unsigned-integer-size(8)>>, :uint, :ChromaSitingHorz) do
    case type do
      0 -> :unspecified
      1 -> :left_collocated
      2 -> :half
    end
  end

  defp parse(<<type::unsigned-integer-size(8)>>, :uint, :ChromaSitingVert) do
    case type do
      0 -> :unspecified
      1 -> :top_collocated
      2 -> :half
    end
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.1
  defp parse(<<>>, :integer, _name) do
    0
  end

  defp parse(bytes, :integer, _name) do
    s = bit_size(bytes)
    <<num::signed-big-integer-size(s)>> = bytes
    num
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.2
  defp parse(<<>>, :uint, _name) do
    0
  end

  defp parse(bytes, :uint, _name) do
    :binary.decode_unsigned(bytes, :big)
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.3
  defp parse(<<>>, :float, _name) do
    0
  end

  defp parse(<<num::float-big>>, :float, _name) do
    num
  end

  # The demuxer MUST only open webm DocType files.
  # per demuxer guidelines https://www.webmproject.org/docs/container/
  defp parse(bytes, :string, :DocType) do
    case parse(bytes, :string, nil) do
      "webm" -> "webm"
      type -> raise "The file DocType is '#{type}' but it MUST be 'webm'"
    end
  end

  defp parse(bytes, :string, :CodecID) do
    case parse(bytes, :string, nil) do
      "A_OPUS" -> :opus
      "A_VORBIS" -> :vorbis
      "V_VP8" -> :vp8
      "V_VP9" -> :vp9
    end
  end

  defp parse(bytes, :string, _name) do
    chars = for <<c::utf8 <- bytes>>, do: <<c::utf8>>
    chars |> Enum.take_while(fn c -> c != <<0>> end) |> Enum.join()
  end

  defp parse(bytes, :utf_8, _name) do
    bytes
    |> String.codepoints()
    |> Enum.reduce("", fn codepoint, result ->
      <<parsed::8>> = codepoint
      if parsed == 0, do: result, else: result <> <<parsed>>
    end)
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.6
  defp parse(<<>>, :date, _name) do
    {{2001, 1, 1}, {0, 0, 0}}
  end

  defp parse(<<nanoseconds::big-signed>>, :date, _name) do
    seconds_zero = :calendar.datetime_to_gregorian_seconds({{2001, 1, 1}, {0, 0, 0}})
    seconds = div(nanoseconds, Time.nanosecond()) + seconds_zero
    :calendar.gregorian_seconds_to_datetime(seconds)
  end

  # TODO: handle Block, BlockGroup

  # https://tools.ietf.org/id/draft-lhomme-cellar-matroska-04.html#rfc.section.6.2.4.4
  defp parse(bytes, :binary, :SimpleBlock) do
    # track_number is a vint with size 1 or 2 bytes
    {track_number, body} = EBML.decode_vint(bytes)

    <<timecode::integer-signed-big-size(16), keyframe::1, reserved::3, invisible::1, lacing::2,
      discardable::1, data::binary>> = body

    lacing =
      case lacing do
        0b00 -> :no_lacing
        0b01 -> :Xiph_lacing
        0b11 -> :EBML_lacing
        0b10 -> :fixed_size_lacing
      end

    # TODO: deal with lacing != 00 https://tools.ietf.org/id/draft-lhomme-cellar-matroska-04.html#laced-data-1

    %{
      track_number: track_number,
      timecode: timecode,
      header_flags: %{
        keyframe: keyframe == 1,
        reserved: reserved,
        invisible: invisible == 1,
        lacing: lacing,
        discardable: discardable == 1
      },
      data: data
    }
  end

  defp parse(bytes, :binary, _name) do
    bytes
  end

  defp parse(bytes, :void, _name) do
    byte_size(bytes)
  end

  defp parse(bytes, :unknown, _name) do
    Base.encode16(bytes)
  end

  defp parse(bytes, :ignore, _name) do
    Base.encode16(bytes)
  end
end
