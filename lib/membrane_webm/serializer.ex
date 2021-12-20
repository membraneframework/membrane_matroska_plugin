defmodule Membrane.WebM.Serializer do
  @moduledoc """
  Module for serializing WebM elements into writable bytes.

  """
  alias Membrane.WebM.Parser.EBML
  alias Membrane.WebM.Schema

  use Bitwise

  @print_blocks false
  @print_elements true

  def serialize({name, data}) do
    type = Schema.element_type(name)
    serialize(data, type, name)
  end

  defp generic_serialize(element_data, type, name) do
    if @print_elements and name != :SimpleBlock, do: IO.puts("serialize #{type} #{name}")

    element_id = EBML.encode_element_id(name)
    element_data_size = byte_size(element_data) |> EBML.encode_vint()

    element_id <> element_data_size <> element_data
  end

  defp serialize(elements, :master, name) do
    element_data =
      Enum.reduce(elements, <<>>, fn {name, data}, acc -> serialize({name, data}) <> acc end)

    generic_serialize(element_data, :master, name)
  end

  defp serialize(uint, :uint, name) do
    element_data = :binary.encode_unsigned(uint, :big)

    generic_serialize(element_data, :uint, name)
  end

  defp serialize(string, :string, name) do
    generic_serialize(string, :string, name)
  end

  # FIXME: I'm not sure if this get's encoded properly
  defp serialize(string, :utf_8, name) do
    generic_serialize(string, :utf_8, name)
  end

  defp serialize(num, :float, name) do
    element_data = <<num::float-big>>

    generic_serialize(element_data, :float, name)
  end

  defp serialize(length, :void, name) do
    # FIXME: i don't see how to avoid funny business on 2^(7*n) +- 1 lengths
    n = trunc(:math.log2(length - 1) / 7) + 1
    length = (length - n - 1) * 8
    element_data = <<0::size(length)>>

    generic_serialize(element_data, :void, name)
  end

  defp serialize({timecode, data, track_number, type}, :binary, :SimpleBlock) do
    if @print_blocks, do: IO.puts("serialize #{type} simpleblock")

    cond do
      type == :opus ->
        serialize_opus_frame(data, timecode, track_number)

      type == :vp8 or type == :vp9 ->
        serialize_vpx_frame(data, timecode, track_number, type)
    end
  end

  defp serialize(bytes, :binary, name) do
    generic_serialize(bytes, :binary, name)
  end

  defp serialize_opus_frame(data, timecode, track_number) do
    # flags
    #          value::number_of_bits
    # keyframe:    1::0     # always 1    - no mention of keyframes in Opus RFC
    # reserved:    0::3     # always 000  - per Matroska RFC
    # invisible:   0::1     # always 0    - assumed
    # lacing:      0::2     # always 00   - no mention in Opus RFC
    # discardable: 0::1     # always 0    - assumed
    header_flags = <<1::1, 0::7>>
    # header_flags = <<0b1000000>>
    timecode = <<timecode::integer-signed-big-size(16)>>
    element_data = EBML.encode_vint(track_number) <> timecode <> header_flags <> data

    generic_serialize(element_data, :master, :SimpleBlock)
  end

  # flags in VP8 RFC:
  # https://datatracker.ietf.org/doc/html/rfc6386#section-9.1
  defp serialize_vpx_frame(data, timecode, track_number, type) do
    timecode = <<timecode::integer-signed-big-size(16)>>
    keyframe =  case type do
      :vp8 -> vp8_frame_type(data)
      :vp9 -> vp9_frame_type(data)
    end
    header_flags = <<keyframe::1, 0::7>>
    element_data = EBML.encode_vint(track_number) <> timecode <> header_flags <> data

    generic_serialize(element_data, :master, :SimpleBlock)
  end

  def vp8_frame_type(<<frame_tag::binary-size(3), _rest::bitstring>>) do
    <<size_0::3, _show_frame::1, _version::3, keyframe::1, size_1, size_2>> = frame_tag
    <<_size::19>> = <<size_2, size_1, size_0::3>>

    keyframe
  end

  # this assumes a simple frame and not a superframe
  # See [PDF download] https://storage.googleapis.com/downloads.webmproject.org/docs/vp9/vp9-bitstream-specification-v0.6-20160331-draft.pdf
  # page 25 for frame structure
  # page 28 for uncompressed header structure
  # TODO: possible headache: VP9 supports superframes which glue several frames together (simple concatenation, page 26)
  # frame_type = 0 means keyframe
  # frame_type = 1 means interframe
  def vp9_frame_type(frame) do
    case frame do
      <<_frame_marker::2, 1::1, 1::1, 0::1, 1::1, _frame_to_show_map_idx::3, frame_type::1,
        _rest::bitstring>> ->
        frame_type

      <<_frame_marker::2, 1::1, 1::1, 0::1, 0::1, frame_type::1, _rest::bitstring>> ->
        frame_type

      <<_frame_marker::2, _low::1, _high::1, 1::1, _frame_to_show_map_idx::3, frame_type::1,
        _rest::bitstring>> ->
        frame_type

      <<_frame_marker::2, _low::1, _high::1, 0::1, frame_type::1, _rest::bitstring>> ->
        frame_type

      _ ->
        raise "Invalid vp9 header"
    end
  end
end
