defmodule Membrane.WebM.Parser.Codecs do
  # These functions should be provided by VP8, VP9 and Opus plugins but they aren't

  alias Membrane.{Opus, VP8, VP9}

  def vp8_frame_is_keyframe(<<frame_tag::binary-size(3), _rest::bitstring>>) do
    <<size_0::3, _show_frame::1, _version::3, frame_type::1, size_1, size_2>> = frame_tag
    <<_size::19>> = <<size_2, size_1, size_0::3>>

    frame_type == 0
  end

  # this assumes a simple frame and not a superframe
  # See [PDF download] https://storage.googleapis.com/downloads.webmproject.org/docs/vp9/vp9-bitstream-specification-v0.6-20160331-draft.pdf
  # page 25 for frame structure
  # page 28 for uncompressed header structure
  # TODO: possible headache: VP9 supports superframes which glue several frames together (simple concatenation, page 26)
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

        _ ->
          raise "Invalid vp9 header"
      end

    frame_type == 0
  end

  def is_video_keyframe({_timecode, _data, _track_number, codec} = block) do
    is_video(codec) and keyframe_bit(block) == 1
  end

  def is_audio(codec) do
    case codec do
      %Opus{} -> true
      _ -> false
    end
  end

  def is_video(codec) do
    case codec do
      %VP8{} -> true
      %VP9{} -> true
      _ -> false
    end
  end

  def keyframe_bit({_timecode, data, _track_number, codec} = _block) do
    case codec do
      %VP8{} -> vp8_frame_is_keyframe(data) |> boolean_to_integer
      %VP9{} -> vp9_frame_is_keyframe(data) |> boolean_to_integer
      %Opus{} -> 1
      _ -> 0
    end
  end

  def boolean_to_integer(bool) do
    if bool, do: 1, else: 0
  end

  # ID header of the Ogg Encapsulation for the Opus Audio Codec
  # Used to populate the TrackEntry.CodecPrivate field
  # Required for correct playback of Opus tracks with more than 2 channels
  # https://datatracker.ietf.org/doc/html/rfc7845#section-5.1
  def construct_opus_id_header(channels) do
    if channels > 2 do
      raise "Handling Opus channel counts of #{channels} is not supported. Cannot mux into a playable form."
    end

    # option descriptions copied over from ogg_plugin:
    # original_sample_rate: [
    #   type: :non_neg_integer,
    #   default: 0,
    #   description: """
    #   Optionally, you may pass the original sample rate of the source (before it was encoded).
    #   This is considered metadata for Ogg/Opus. Leave this at 0 otherwise.
    #   See https://tools.ietf.org/html/rfc7845#section-5.
    #   """
    # ],
    # output_gain: [
    #   type: :integer,
    #   default: 0,
    #   description: """
    #   Optionally, you may pass a gain change when decoding.
    #   You probably shouldn't though. Instead apply any gain changes using Membrane itself, if possible.
    #   See https://tools.ietf.org/html/rfc7845#section-5
    #   """
    # ],
    # pre_skip: [
    #   type: :non_neg_integer,
    #   default: 0,
    #   description: """
    #   Optionally, you may as a number of samples (at 48kHz) to discard
    #   from the decoder output when starting playback.
    #   See https://tools.ietf.org/html/rfc7845#section-5
    #   """
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
