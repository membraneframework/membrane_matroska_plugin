defmodule Membrane.WebM.Parser.WebM do
  @moduledoc false
  # special parsing rules for matroska elements
  # note that when matroska and webm conflict webm takes precedence

  alias Membrane.WebM.Parser.EBML
  alias Membrane.WebM.Schema

  @spec parse(binary, atom) :: any
  def parse(<<type::unsigned-integer-size(8)>>, :TrackType) do
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

  def parse(<<type::unsigned-integer-size(8)>>, :FlagInterlaced) do
    case type do
      # Unknown status.This value SHOULD be avoided.
      0 -> :undetermined
      # Interlaced frames.
      1 -> :interlaced
      # No interlacing.
      2 -> :progressive
    end
  end

  def parse(<<type::unsigned-integer-size(8)>>, :ChromaSitingHorz) do
    case type do
      0 -> :unspecified
      1 -> :left_collocated
      2 -> :half
    end
  end

  def parse(<<type::unsigned-integer-size(8)>>, :ChromaSitingVert) do
    case type do
      0 -> :unspecified
      1 -> :top_collocated
      2 -> :half
    end
  end

  def parse(<<type::unsigned-integer-size(8)>>, :StereoMode) do
    # Stereo-3D video mode.
    # WebM Supported Modes: 0, 1, 2, 3, 11
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

  # The demuxer MUST only open webm DocType files.
  # per demuxer guidelines https://www.webmproject.org/docs/container/
  def parse(bytes, :DocType) do
    text = EBML.parse(bytes, :string)

    case text do
      "webm" -> "webm"
      type -> raise "The file DocType is '#{type}' but it MUST be 'webm'"
    end
  end

  def parse(bytes, :CodecID) do
    text = EBML.parse(bytes, :string)

    case text do
      "A_OPUS" -> :opus
      "A_VORBIS" -> :vorbis
      "V_VP8" -> :vp8
      "V_VP9" -> :vp9
      codec -> raise "WebM contains illegal codec #{codec}"
    end
  end

  # codec state is stored in :Block, :BlockGroup elements
  # it probably contains information about the next I-frame or some such
  # for now it seems that it can be safely ignored - every frame is inside a :SimpleBlock

  # https://tools.ietf.org/id/draft-lhomme-cellar-matroska-04.html#rfc.section.6.2.4.4
  def parse(bytes, :SimpleBlock) do
    # track_number is a vint with size 1 or 2 bytes
    {:ok, {track_number, body}} = EBML.decode_vint(bytes)

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

  # non-special-case elements should be handled generically by the EBML parser
  def parse(bytes, name) do
    type = Schema.element_type(name)
    EBML.parse(bytes, type)
  end
end
