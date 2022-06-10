defmodule Membrane.Matroska.Parser.Matroska do
  @moduledoc false

  alias Membrane.Matroska.Parser.EBML

  @spec parse_track_type(binary) :: atom
  def parse_track_type(<<type::unsigned-integer-size(8)>>) do
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

  @spec parse_flag_interlaced(binary) :: atom
  def parse_flag_interlaced(<<type::unsigned-integer-size(8)>>) do
    case type do
      # Unknown status.This value SHOULD be avoided.
      0 -> :undetermined
      # Interlaced frames.
      1 -> :interlaced
      # No interlacing.
      2 -> :progressive
    end
  end

  @spec parse_chroma_siting_horz(binary) :: atom
  def parse_chroma_siting_horz(<<type::unsigned-integer-size(8)>>) do
    case type do
      0 -> :unspecified
      1 -> :left_collocated
      2 -> :half
    end
  end

  @spec parse_chroma_siting_vert(binary) :: atom
  def parse_chroma_siting_vert(<<type::unsigned-integer-size(8)>>) do
    case type do
      0 -> :unspecified
      1 -> :top_collocated
      2 -> :half
    end
  end

  @spec parse_stereo_mode(binary) :: atom
  def parse_stereo_mode(<<type::unsigned-integer-size(8)>>) do
    # Stereo-3D video mode.
    # Matroska Supported Modes: 0, 1, 2, 3, 11
    # See https://www.webmproject.org/docs/container/#StereoMode

    case type do
      0 -> :mono
      1 -> :side_by_side_left_eye_first
      2 -> :top_bottom_right_eye_is_first
      3 -> :top_bottom_left_eye_is_first
      # 4	checkboard (right eye is first)
      # 5	checkboard (left eye is first)
      # 6	row interleaved (right eye is first)
      # 7	row interleaved (left eye is first)
      # 8	column interleaved (right eye is first)
      # 9	column interleaved (left eye is first)
      # 10	anaglyph (cyan/red)
      11 -> :side_by_side_right_eye_first
      # 12	anaglyph (green/magenta)
      # 13	both eyes laced in one Block (left eye is first)
      # 14	both eyes laced in one Block (right eye is first)
      _other -> :unsupported
    end
  end

  @spec parse_doc_type(binary) :: binary
  def parse_doc_type(bytes) do
    text = EBML.parse_string(bytes)

    case text do
      "webm" -> "webm"
      "matroska" -> "matroska"
      type -> raise "The file DocType is '#{type}' but it MUST be 'matroska' or 'webm' "
    end
  end

  @spec parse_codec_id(binary) :: :opus | :vorbis | :vp8 | :vp9
  def parse_codec_id(bytes) do
    text = EBML.parse_string(bytes)

    case text do
      "A_OPUS" -> :opus
      "A_VORBIS" -> :vorbis
      "V_VP8" -> :vp8
      "V_VP9" -> :vp9
      "V_MPEG4/ISO/AVC" -> :h264
      codec -> raise "Matroska contains illegal codec #{codec}"
    end
  end

  @spec parse_block(binary) :: %{
          data: binary,
          header_flags: %{
            discardable: boolean,
            invisible: boolean,
            lacing: :EBML_lacing | :Xiph_lacing | :fixed_size_lacing | :no_lacing
          },
          timecode: integer,
          track_number: non_neg_integer
        }
  def parse_block(bytes) do
    # track_number is a vint with size 1 or 2 bytes
    {:ok, {track_number, body}} = EBML.decode_vint(bytes)

    <<timecode::integer-signed-big-size(16), _reserved::3, invisible::1, lacing::2,
      discardable::1, _unused::1, data::binary>> = body

    %{
      track_number: track_number,
      timecode: timecode,
      header_flags: %{
        invisible: invisible == 1,
        lacing: check_lacing_mode(lacing),
        discardable: discardable == 1
      },
      data: data
    }
  end

  # https://tools.ietf.org/id/draft-lhomme-cellar-matroska-04.html#rfc.section.6.2.4.4
  @spec parse_simple_block(binary) :: %{
          data: binary,
          header_flags: %{
            discardable: boolean,
            invisible: boolean,
            keyframe: boolean,
            lacing: :EBML_lacing | :Xiph_lacing | :fixed_size_lacing | :no_lacing
          },
          timecode: integer,
          track_number: non_neg_integer
        }
  def parse_simple_block(bytes) do
    # track_number is a vint with size 1 or 2 bytes
    {:ok, {track_number, body}} = EBML.decode_vint(bytes)

    <<timecode::integer-signed-big-size(16), keyframe::1, _reserved::3, invisible::1, lacing::2,
      discardable::1, data::binary>> = body

    %{
      track_number: track_number,
      timecode: timecode,
      header_flags: %{
        keyframe: keyframe == 1,
        invisible: invisible == 1,
        lacing: check_lacing_mode(lacing),
        discardable: discardable == 1
      },
      data: data
    }
  end

  defp check_lacing_mode(mode) do
    case mode do
      0b00 ->
        :no_lacing

      # Other possible lacing modes which are not supported now
      # 0b01 -> :Xiph_lacing
      # 0b11 -> :EBML_lacing
      # 0b10 -> :fixed_size_lacing

      _any_lacing ->
        raise "Demuxing matroska files with laced data is currently not supported"
    end
  end
end
