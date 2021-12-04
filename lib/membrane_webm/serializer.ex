defmodule Membrane.WebM.Serializer do
  @moduledoc """
  Module for serializing WebM elements into writable bytes.

  """
  alias Membrane.Time
  alias Membrane.WebM.Parser.Vint
  alias Membrane.WebM.Schema

  def serialize(name, data) do
    type = Schema.element_type(name)
    serialize(data, type, name)
  end

  def serialize_many(elements) do
    Enum.reduce(elements, <<>>, fn {name, data}, acc -> [serialize(name, data) | acc] end)
  end

  def serialize(data, :master, name) do
    _element_id = name |> Schema.name_to_element_id() |> Vint.encode_element_id()
    serialize_many(data)
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.1
  def serialize(<<>>, :integer, _name) do
    0
  end

  def serialize(bytes, :integer, _name) do
    s = byte_size(bytes) * 8
    <<num::signed-big-integer-size(s)>> = bytes
    num
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.2
  def serialize(<<>>, :uint, _name) do
    0
  end

  def serialize(bytes, :uint, _name) do
    :binary.decode_unsigned(bytes, :big)
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.3
  def serialize(<<>>, :float, _name) do
    0
  end

  def serialize(<<num::float-big>>, :float, _name) do
    num
  end

  def serialize(bytes, :string, :CodecID) do
    codec_string = Enum.join(for <<c::utf8 <- bytes>>, do: <<c::utf8>>)

    case codec_string do
      "A_OPUS" -> :opus
      "A_VORBIS" -> :vorbis
      "V_VP8" -> :vp8
      "V_VP9" -> :vp9
    end
  end

  def serialize(bytes, :string, _name) do
    chars = for <<c::utf8 <- bytes>>, do: <<c::utf8>>
    chars |> Enum.take_while(fn c -> c != <<0>> end) |> Enum.join()
  end

  def serialize(bytes, :utf_8, _name) do
    bytes
    |> String.codepoints()
    |> Enum.reduce("", fn codepoint, result ->
      <<serialized::8>> = codepoint
      if serialized == 0, do: result, else: result <> <<serialized>>
    end)
  end

  # per RFC https://datatracker.ietf.org/doc/html/rfc8794#section-7.6
  def serialize(<<>>, :date, _name) do
    {{2001, 1, 1}, {0, 0, 0}}
  end

  def serialize(<<nanoseconds::big-signed>>, :date, _name) do
    seconds_zero = :calendar.datetime_to_gregorian_seconds({{2001, 1, 1}, {0, 0, 0}})
    seconds = div(nanoseconds, Time.nanosecond()) + seconds_zero
    :calendar.gregorian_seconds_to_datetime(seconds)
  end

  # https://tools.ietf.org/id/draft-lhomme-cellar-matroska-04.html#rfc.section.6.2.4.4
  def serialize(bytes, :binary, :SimpleBlock) do
    # track_number is a vint with size 1 or 2 bytes
    %{vint: track_number_vint, rest: body} = Vint.serialize(bytes)

    <<timecode::integer-signed-size(16), keyframe::1, reserved::3, invisible::1, lacing::2,
      discardable::1, data::binary>> = body

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

  def serialize(bytes, :binary, _name) do
    bytes
  end

  def serialize(bytes, :void, _name) do
    byte_size(bytes)
  end

  def serialize(bytes, :unknown, _name) do
    Base.encode16(bytes)
  end

  def serialize(bytes, :ignore, _name) do
    Base.encode16(bytes)
  end
end
