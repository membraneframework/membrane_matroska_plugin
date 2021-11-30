defmodule Membrane.WebM.Parser do
  use Membrane.Filter

  alias Membrane.{Buffer, Time}
  alias Membrane.WebM.Parser.Vint
  alias Membrane.WebM.Schema

  def_input_pad :input,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers,
    caps: :any

  def_output_pad :output,
    availability: :always,
    mode: :pull,
    caps: :any

  defmodule State do
    @moduledoc false
    defstruct [:acc]
  end

  @return_elements [
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
    {:ok, %State{acc: <<>>}}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _context, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload}, _context, %State{acc: acc} = state) do
    unparsed = acc <> payload

    case parse_many(unparsed, []) do
      {:ok, {name, data} = result, rest} ->
        IO.puts("    Parser sending #{name}")
        # , {:redemand, :output}
        {{:ok, buffer: {:output, %Buffer{payload: result}}}, %State{acc: rest}}

      :need_more_bytes ->
        {{:ok, redemand: :output}, %State{acc: unparsed}}
    end
  end

  # if parsing top element and encountered new top element or rest is empty: you done, bro. not necessarily

  def parse_many(bytes, acc) do
    case parse_element(bytes) do
      %{element: {name, _data} = element, rest: rest} ->
        if name in @return_elements do
          {:ok, element, rest}
        else
          if rest == <<>> do
            [element | acc]
          else
            parse_many(rest, [element | acc])
          end
        end

      :need_more_bytes ->
        :need_more_bytes

      {:ok, element, rest} ->
        {:ok, element, rest}
    end
  end

  def parse_element(bytes) do
    %{vint: vint, rest: bytes} = Vint.parse(bytes)
    id = vint.element_id
    %{vint: vint, rest: bytes} = Vint.parse(bytes)
    # TODO: deal with unknown data size
    data_size = vint.vint_data
    name = Schema.element_id_to_name(id)
    type = Schema.element_type(name)

    # if name == :Unknown do
    #   IO.warn("unknown element ID: #{id}")
    # end

    if name == :Segment do
      parse_many(bytes, [])
    else
      case trim_bytes(bytes, data_size) do
        %{bytes: data, rest: rest} ->
          element = {name, parse(data, type, name)}
          %{element: element, rest: rest}

        :need_more_bytes ->
          :need_more_bytes
      end
    end
  end

  def trim_bytes(bytes, how_many) do
    if how_many > byte_size(bytes) do
      :need_more_bytes
    else
      <<bytes::binary-size(how_many), rest::binary>> = bytes
      %{bytes: bytes, rest: rest}
    end
  end

  def parse(bytes, :master, _name) do
    if byte_size(bytes) == 0 do
      []
    else
      parse_many(bytes, [])
    end
  end

  def parse(<<type::unsigned-integer-size(8)>>, :uint, :TrackType) do
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

  def parse(<<type::unsigned-integer-size(8)>>, :uint, :FlagInterlaced) do
    case type do
      # Unknown status.This value SHOULD be avoided.
      0 -> :undetermined
      # Interlaced frames.
      1 -> :interlaced
      # No interlacing.
      2 -> :progressive
    end
  end

  def parse(<<type::unsigned-integer-size(8)>>, :uint, :ChromaSitingHorz) do
    case type do
      0 -> :unspecified
      1 -> :left_collocated
      2 -> :half
    end
  end

  def parse(<<type::unsigned-integer-size(8)>>, :uint, :ChromaSitingVert) do
    case type do
      0 -> :unspecified
      1 -> :top_collocated
      2 -> :half
    end
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.1
  def parse(<<>>, :integer, _name) do
    0
  end

  def parse(bytes, :integer, _name) do
    s = byte_size(bytes) * 8
    <<num::signed-big-integer-size(s)>> = bytes
    num
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.2
  def parse(<<>>, :uint, _name) do
    0
  end

  def parse(bytes, :uint, _name) do
    :binary.decode_unsigned(bytes, :big)
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.3
  def parse(<<>>, :float, _name) do
    0
  end

  def parse(<<num::float-big>>, :float, _name) do
    num
  end

  def parse(bytes, :string, :CodecID) do
    codec_string = Enum.join(for <<c::utf8 <- bytes>>, do: <<c::utf8>>)

    case codec_string do
      "A_OPUS" -> :opus
      "A_VORBIS" -> :vorbis
      "V_VP8" -> :vp8
      "V_VP9" -> :vp9
    end
  end

  def parse(bytes, :string, _name) do
    chars = for <<c::utf8 <- bytes>>, do: <<c::utf8>>
    chars |> Enum.take_while(fn c -> c != <<0>> end) |> Enum.join()
  end

  def parse(bytes, :utf_8, _name) do
    bytes
    |> String.codepoints()
    |> Enum.reduce("", fn codepoint, result ->
      <<parsed::8>> = codepoint
      if parsed == 0, do: result, else: result <> <<parsed>>
    end)
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.6
  def parse(<<>>, :date, _name) do
    {{2001, 1, 1}, {0, 0, 0}}
  end

  def parse(<<nanoseconds::big-signed>>, :date, _name) do
    seconds_zero = :calendar.datetime_to_gregorian_seconds({{2001, 1, 1}, {0, 0, 0}})
    seconds = div(nanoseconds, Time.nanosecond()) + seconds_zero
    :calendar.gregorian_seconds_to_datetime(seconds)
  end

  def parse(bytes, :binary, :SimpleBlock) do
    # https://tools.ietf.org/id/draft-lhomme-cellar-matroska-04.html#rfc.section.6.2.4.4

    # track_number is a vint with size 1 or 2 bytes
    %{vint: track_number_vint, rest: body} = Vint.parse(bytes)
    <<timecode::integer-signed-size(16), flags::bitstring-size(8), data::binary>> = body
    <<keyframe::1, reserved::3, invisible::1, lacing::2, discardable::1>> = flags

    if reserved != 0 do
      IO.warn("SimpleBlock reserved bits in header flag should all be 0 but they are #{reserved}")
    end

    lacing =
      case lacing do
        0b00 -> :no_lacing
        0b01 -> :Xiph_lacing
        0b11 -> :EBML_lacing
        0b10 -> :fixed_size_lacing
      end

    # TODO deal with lacing != 00 https://tools.ietf.org/id/draft-lhomme-cellar-matroska-04.html#laced-data-1

    %{
      track_number: track_number_vint.vint_data,
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

  def parse(bytes, :binary, _name) do
    bytes
    # Base.encode16(bytes)
  end

  def parse(bytes, :void, _name) do
    # Base.encode16(bytes)
    byte_size(bytes)
  end

  def parse(bytes, :unknown, _name) do
    Base.encode16(bytes)
  end

  def parse(bytes, :ignore, _name) do
    Base.encode16(bytes)
  end
end
