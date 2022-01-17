defmodule Membrane.WebM.Parser.Matroska do
  alias Membrane.WebM.Parser.EBML

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

  # The demuxer MUST only open webm DocType files.
  # per demuxer guidelines https://www.webmproject.org/docs/container/
  def parse(bytes, :string, :DocType) do
    case parse(bytes, :string, nil) do
      "webm" -> "webm"
      type -> raise "The file DocType is '#{type}' but it MUST be 'webm'"
    end
  end

  def parse(bytes, :string, :CodecID) do
    case parse(bytes, :string, nil) do
      "A_OPUS" -> :opus
      "A_VORBIS" -> :vorbis
      "V_VP8" -> :vp8
      "V_VP9" -> :vp9
    end
  end

  # TODO: handle Block, BlockGroup - codec_data will be stored here

  # https://tools.ietf.org/id/draft-lhomme-cellar-matroska-04.html#rfc.section.6.2.4.4
  def parse(bytes, :binary, :SimpleBlock) do
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
  def parse(bytes, type, _name) do
    EBML.parse(bytes, type)
  end
end
