defmodule Membrane.WebM.Schema do
  @moduledoc """
  WebM structure schema for muxing and demuxing

  A WebM file is defined as a Matroska file that satisfies strict constraints.
  A Matroska file is an EBML file (Extendable-Binary-Meta-Language) with one segment and certain other constraints.

  Docs:
  - EBML https://www.rfc-editor.org/rfc/rfc8794.html
  - WebM https://www.webmproject.org/docs/container/
  - Matroska https://matroska.org/technical/basics.html

  WebM codec formats:
  - Video: VP8 or VP9
  - Audio: Vorbis or Opus
  """

  # @typedoc """
  #   A typical EBML file has the following structure:
  # [Matroska]
  # [WebM]
  # EBML Header (master)
  # + DocType (string)
  # + DocTypeVersion (unsigned integer)
  # EBML Body Root (master)
  # + ElementA (utf-8)
  # + Parent (master)
  # + ElementB (integer)
  # + Parent (master)
  # + ElementB (integer)
  # """
  # @type ebml :: nil

  # @ebml_element %{element_id: :  element_data_size: :vint, element_data: :vint}

  # @vint [
  #   vint_width: "zero or no bits of value 0 terminated by `:vint_marker`",
  #   vint_marker: "1",
  #   vint_data: "7 * (1 + :vint_width) bits of usable data. data must be left-padded with 0's"
  #   # The VINT_DATA value be expressed as a big-endian unsigned integer.
  # ]

  def classify_element(element_id) do
    case element_id do
      ### EBML elements:

      "1A45DFA3" -> {:EBML, :master}
      "4286" -> {:EBMLVersion, :uint}
      "42F7" -> {:EBMLReadVersion, :uint}
      "42F2" -> {:EBMLMaxIDLength, :uint}
      "42F3" -> {:EBMLMaxSizeLength, :uint}
      "4282" -> {:DocType, :string}
      "4287" -> {:DocTypeVersion, :uint}
      "4285" -> {:DocTypeReadVersion, :uint}
      "4281" -> {:DocTypeExtension, :master}
      "4283" -> {:DocTypeExtensionName, :string}
      "4284" -> {:DocTypeExtensionVersion, :uint}
      # "BF" -> {:CRC_32, :crc_32} unsupported by WebM
      "EC" -> {:Void, :void}

      ### Matroska elements:

      "18538067" -> {:Segment, :master}
        # \Segment

        "1C53BB6B" -> {:Cues, :master}
          # \Segment\Cues
          "BB" -> {:CuePoint, :master}
            # \Segment\Cues\CuePoint
            "B3" -> {:CueTime, :uint}
            "B7" -> {:CueTrackPositions, :master}
              # \Segment\Cues\CuePoint\CueTrackPositions
              "F0" -> {:CueRelativePosition, :uint}
              "F1" -> {:CueClusterPosition, :uint}
              "F7" -> {:CueTrack, :uint}
              "B2" -> {:CueDuration, :unit}
              "5378" -> {:CueBlockNumber, :uint}
        # data is stored here:
        "1F43B675" -> {:Cluster, :master}
        # \Segment\Cluster
          "A3" -> {:SimpleBlock, :binary}
          "E7" -> {:Timecode, :uint}
          "AB" -> {:PrevSize, :uint}
          "A0" -> {:BlockGroup, :master}
          # \Segment\Cluster\BlockGroup
            "A1" -> {:Block, :binary}
            "75A1" -> {:BlockAdditions, :master}
              # \Segment\Cluster\BlockGroup
              "A6" -> {:BlockMore, :master}
                # \Segment\Cluster\BlockGroup\BlockMore
                  "EE" -> {:BlockAddID, :uint}
                  "A5" -> {:BlockAdditional, :binary}
            "9B" -> {:BlockDuration, :uint}
            "FB" -> {:ReferenceBlock, :integer}
            "75A2" -> {:DiscardPadding, :integer}
        # Deprecated	BlockVirtual
        # Deprecated	TimeSlice
        # Deprecated	LaceNumber

        "1254C367" -> {:Tags, :master}
        # \Segment\Tags
          "7373" -> {:Tag, :master}
          # \Segment\Tags\Tag
          "63C0" -> {:Targets, :master}
            # \Segment\Tags\Tag\Targets
            "68CA" -> {:TargetTypeValue, :uint}
            "63CA" -> {:TargetType, :string}
            "63C5" -> {:TagTrackUID, :uint}
          "67C8" -> {:SimpleTag, :master}
            # \Segment\Tags\Tag\SimpleTag
            "4487" -> {:TagString, :utf_8}
            "45A3" -> {:TagName, :utf_8}
            "447A" -> {:TagLanguage, :string}
            "4484" -> {:TagDefault, :uint}
            "4485" -> {:TagBinary, :binary}
        "1654AE6B" -> {:Tracks, :master}
          # \Segment\Tracks
          "AE" -> {:TrackEntry, :master}
            # \Segment\Tracks\TrackEntry
            "D7" -> {:TrackNumber, :uint}
            "73C5" -> {:TrackUID, :uint}
            "B9" -> {:FlagEnabled, :unit}
            "88" -> {:FlagDefault, :uint}
            "55AA" -> {:FlagForced, :uint}
            "9C" -> {:FlagLacing, :uint}
            "22B59C" -> {:Language, :string}
            "86" -> {:CodecID, :string}
            "56AA" -> {:CodecDelay, :uint}
            "56BB" -> {:SeekPreRoll, :uint}
            "536E" -> {:Name, :utf_8}
            "83" -> {:TrackType, :uint}
            "63A2" -> {:CodecPrivate, :binary}
            "258688" -> {:CodecName, :utf_8}
            "E1" -> {:Audio, :master}
            "23E383" ->{:DefaultDuration, :uint}
              # \Segment\Tracks\TrackEntry\Audio
              "9F" -> {:Channels, :uint}
              "B5" -> {:SamplingFrequency, :float}
              "6264" -> {:BitDepth, :uint}
            "E0" -> {:Video, :master}
              # \Segment\Tracks\TrackEntry\Video
              "B0" -> {:PixelWidth, :uint}
              "BA" -> {:PixelHeight, :uint}
              "9A" -> {:FlagInterlaced, :uint}
              # StereoMode
              #     Supported Modes: 0: mono, 1: side by side (left eye is first), 2: top-bottom (right eye is first), 3: top-bottom (left eye is first), 11: side by side (right eye is first)
              #     Unsupported Modes: 4: checkboard (right is first), 5: checkboard (left is first), 6: row interleaved (right is first), 7: row interleaved (left is first), 8: column interleaved (right is first), 9: column interleaved (left is first), 10: anaglyph (cyan/red)
              "55B0" -> {:Colour, :master}
              # \Segment\Tracks\TrackEntry\Video\Colour
              "55B7" -> {:ChromaSitingHorz, :uint}
              "55B8" -> {:ChromaSitingVert, :uint}

#               # Video Start
# AlphaMode
# PixelCropBottom
# PixelCropTop
# PixelCropLeft
# PixelCropRight
# DisplayWidth
# DisplayHeight
# DisplayUnit
# AspectRatioType
# Deprecated	FrameRate
#               # Video End
#               # Audio Start
# Audio
# SamplingFrequency
# OutputSamplingFrequency
# Channels
# BitDepth
#               # Audio End
#               # Content Encoding Start
# ContentEncoding
# ContentEncodingOrder
# ContentEncodingScope
# ContentEncodingType
# ContentEncryption
# ContentEncAlgo
# ContentEncKeyID
# ContentEncAESSettings
# AESSettingsCipherMode
#               # Content Encoding End

                                                  # Colour

                                                  # changing location of the colour element in file https://www.webmproject.org/docs/container/#LuminanceMin
# Colour
# MatrixCoefficients
# BitsPerChannel
# ChromaSubsamplingHorz
# ChromaSubsamplingVert
# CbSubsamplingHorz
# CbSubsamplingVert
### ChromaSitingHorz
### ChromaSitingVert
# Range
# TransferCharacteristics
# Primaries
# MaxCLL
# MaxFALL
# MasteringMetadata
# PrimaryRChromaticityX
# PrimaryRChromaticityY
# PrimaryGChromaticityX
# PrimaryGChromaticityY
# PrimaryBChromaticityX
# PrimaryBChromaticityY
# WhitePointChromaticityX
# WhitePointChromaticityY
# LuminanceMax
# LuminanceMin

                                                  # Chapters

# Chapters
# EditionEntry
# ChapterAtom
# ChapterUID
# ChapterStringUID
# ChapterTimeStart
# ChapterTimeEnd
# ChapterDisplay
# ChapString
# ChapLanguage
# ChapCountry

        "1549A966" -> {:Info, :master}
          # \Segment\Info
          "2AD7B1" -> {:TimecodeScale, :uint}
          "7BA9" -> {:Title, :utf_8}
          "4D80" -> {:MuxingApp, :utf_8}
          "5741" -> {:WritingApp, :utf_8}
          "4489" -> {:Duration, :float}
          "4461" -> {:DateUTC, :date}
        "114D9B74" -> {:SeekHead, :master}
          # \Segment\SeekHead
          "4DBB" -> {:Seek, :master}
            # \Segment\SeekHead\Seek
            "53AC" -> {:SeekPosition, :uint}
            "53AB" -> {:SeekID, :binary}

      _ -> {:UnknownName, :unknown}
    end
  end
end
