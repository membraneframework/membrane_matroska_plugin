defmodule Membrane.Matroska.Parser.Codecs do
  @moduledoc false

  # Utility module containing functions for interacting with Matroska codecs.
  # These functions should be provided by VP8, VP9, Opus, H264 plugins but they aren't.

  # Extracts the keyframe flag from a VP8 stream buffer.
  # See https://datatracker.ietf.org/doc/html/rfc6386#section-9

  alias Membrane.Buffer
  @spec vp8_frame_is_keyframe(binary) :: boolean
  def vp8_frame_is_keyframe(
        <<size_0::3, _show_frame::1, _version::3, frame_type::1, size_1, size_2,
          _rest::bitstring>>
      ) do
    frame_type == 0
  end

  # this assumes a simple frame and not a superframe (page 26)
  # page 25 for frame structure
  # page 28 for uncompressed header structure
  # See [PDF download] https://storage.googleapis.com/downloads.webmproject.org/docs/vp9/vp9-bitstream-specification-v0.6-20160331-draft.pdf
  @spec vp9_frame_is_keyframe(binary) :: boolean
  def vp9_frame_is_keyframe(frame) do
    frame_type =
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

        _invalid ->
          raise "Invalid vp9 header"
      end

    frame_type == 0
  end

  @spec h264_frame_is_keyframe(binary) :: boolean
  def h264_frame_is_keyframe(<<frame_tag::binary-size(3), _rest::bitstring>>) do
    <<size_0::3, _show_frame::1, _version::3, frame_type::1, size_1, size_2>> = frame_tag
    <<_size::19>> = <<size_2, size_1, size_0::3>>

    frame_type == 0
  end

  @spec is_video_keyframe?({integer, Buffer.t(), non_neg_integer, atom}) :: boolean
  def is_video_keyframe?({_timecode, _data, _track_number, codec} = block) do
    type(codec) == :video and keyframe_bit(block) == 1
  end

  @spec type(:opus | :vp8 | :vp9 | :h264) :: :audio | :video
  def type(codec) do
    case codec do
      :opus -> :audio
      :vp8 -> :video
      :vp9 -> :video
      :h264 -> :video
    end
  end

  @spec keyframe_bit({integer, Buffer.t(), non_neg_integer, atom}) :: 0 | 1
  def keyframe_bit({_timecode, %Buffer{payload: data} = buffer, _track_number, codec} = _block) do
    case codec do
      :vp8 ->
        vp8_frame_is_keyframe(data) |> boolean_to_integer

      :vp9 ->
        vp9_frame_is_keyframe(data) |> boolean_to_integer

      :h264 ->
        buffer.metadata.h264.key_frame? |> boolean_to_integer

      :opus ->
        0

      _other ->
        raise "illegal codec #{inspect(codec)}"
    end
  end

  defp boolean_to_integer(bool) do
    if bool, do: 1, else: 0
  end

  # ID header of the Ogg Encapsulation for the Opus Audio Codec
  # Used to populate the TrackEntry.CodecPrivate field
  # Required for correct playback of Opus tracks with more than 2 channels
  # https://datatracker.ietf.org/doc/html/rfc7845#section-5.1
  @spec construct_opus_id_header(1..255) :: binary
  def construct_opus_id_header(channels) do
    if channels > 2,
      do:
        raise(
          "Handling Opus channel count of #{channels} is not supported. Cannot mux into a playable form."
        )

    # for reference see options descriptions in `Membrane.OggPlugin`
    encapsulation_version = 1
    original_sample_rate = 0
    output_gain = 0
    pre_skip = 0
    channel_mapping_family = 0

    [
      "OpusHead",
      <<encapsulation_version::size(8)>>,
      <<channels::size(8)>>,
      <<pre_skip::little-size(16)>>,
      <<original_sample_rate::little-size(32)>>,
      <<output_gain::little-signed-size(16)>>,
      <<channel_mapping_family::size(8)>>
    ]
    |> :binary.list_to_bin()
  end
end
