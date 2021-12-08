defmodule Membrane.WebM.Schema do
  @moduledoc """
  WebM structure schema for muxing and demuxing

  Docs:
    - EBML https://www.rfc-editor.org/rfc/rfc8794.html
    - WebM https://www.webmproject.org/docs/container/
    - Matroska https://matroska.org/technical/basics.html

  A typical WebM file has the following structure:

  EBML
  Segment
  ├── SeekHead
  │   ├── Seek
  │   ├── Seek
  │   ├── Seek
  │   └── Seek
  ├── Void
  ├── Info
  ├── Tracks
  │   └── TrackEntry
  │       └── Video
  │           └── Colour
  ├── Cues
  │   ├── CuePoint
  │   │   └── CueTrackPositions
  │   ├── CuePoint
  │   │   └── CueTrackPositions
  │   ├── CuePoint
  │   │   └── CueTrackPositions
  ...
  ├── Cluster
  │   ├── SimpleBlock
  │   ├── SimpleBlock
  │   ├── SimpleBlock
  │   ├── SimpleBlock
  │   └── SimpleBlock
  ├── Cluster
  │   ├── SimpleBlock
  │   ├── SimpleBlock
  │   ├── SimpleBlock
  │   ├── SimpleBlock
  │   └── SimpleBlock
  """

  @bimap BiMap.new([
           ### EBML elements:
           {"1A45DFA3", :EBML},
           {"4286", :EBMLVersion},
           {"42F7", :EBMLReadVersion},
           {"42F2", :EBMLMaxIDLength},
           {"42F3", :EBMLMaxSizeLength},
           {"4282", :DocType},
           {"4287", :DocTypeVersion},
           {"4285", :DocTypeReadVersion},
           {"4281", :DocTypeExtension},
           {"4283", :DocTypeExtensionName},
           {"4284", :DocTypeExtensionVersion},
           {"EC", :Void},
           ### Matroska elements:
           {"18538067", :Segment},
           # \Segment
           {"1C53BB6B", :Cues},
           # \Segment\Cues
           {"BB", :CuePoint},
           # \Segment\Cues\CuePoint
           {"B3", :CueTime},
           {"B7", :CueTrackPositions},
           # \Segment\Cues\CuePoint\CueTrackPositions
           {"F0", :CueRelativePosition},
           {"F1", :CueClusterPosition},
           {"F7", :CueTrack},
           {"B2", :CueDuration},
           {"5378", :CueBlockNumber},
           # data is stored here:
           {"1F43B675", :Cluster},
           # \Segment\Cluster
           {"A3", :SimpleBlock},
           {"E7", :Timecode},
           {"AB", :PrevSize},
           {"A0", :BlockGroup},
           # \Segment\Cluster\BlockGroup
           {"A1", :Block},
           {"75A1", :BlockAdditions},
           # \Segment\Cluster\BlockGroup
           {"A6", :BlockMore},
           # \Segment\Cluster\BlockGroup\BlockMore
           {"EE", :BlockAddID},
           {"A5", :BlockAdditional},
           {"9B", :BlockDuration},
           {"FB", :ReferenceBlock},
           {"75A2", :DiscardPadding},
           {"1254C367", :Tags},
           # \Segment\Tags
           {"7373", :Tag},
           # \Segment\Tags\Tag
           {"63C0", :Targets},
           # \Segment\Tags\Tag\Targets
           {"68CA", :TargetTypeValue},
           {"63CA", :TargetType},
           {"63C5", :TagTrackUID},
           {"67C8", :SimpleTag},
           # \Segment\Tags\Tag\SimpleTag
           {"4487", :TagString},
           {"45A3", :TagName},
           {"447A", :TagLanguage},
           {"4484", :TagDefault},
           {"4485", :TagBinary},
           {"1654AE6B", :Tracks},
           # \Segment\Tracks
           {"AE", :TrackEntry},
           # \Segment\Tracks\TrackEntry
           {"D7", :TrackNumber},
           {"73C5", :TrackUID},
           {"B9", :FlagEnabled},
           {"88", :FlagDefault},
           {"55AA", :FlagForced},
           {"9C", :FlagLacing},
           {"22B59C", :Language},
           {"86", :CodecID},
           {"56AA", :CodecDelay},
           {"56BB", :SeekPreRoll},
           {"536E", :Name},
           {"83", :TrackType},
           {"63A2", :CodecPrivate},
           {"258688", :CodecName},
           {"E1", :Audio},
           {"23E383", :DefaultDuration},
           # \Segment\Tracks\TrackEntry\Audio
           {"9F", :Channels},
           {"B5", :SamplingFrequency},
           {"6264", :BitDepth},
           {"E0", :Video},
           # \Segment\Tracks\TrackEntry\Video
           {"B0", :PixelWidth},
           {"BA", :PixelHeight},
           {"9A", :FlagInterlaced},
           # StereoMode
           #     Supported Modes: 0: mono, 1: side by side (left eye is first), 2: top-bottom (right eye is first), 3: top-bottom (left eye is first), 11: side by side (right eye is first)
           #     Unsupported Modes: 4: checkboard (right is first), 5: checkboard (left is first), 6: row interleaved (right is first), 7: row interleaved (left is first), 8: column interleaved (right is first), 9: column interleaved (left is first), 10: anaglyph (cyan/red)
           {"55B0", :Colour},
           # \Segment\Tracks\TrackEntry\Video\Colour
           {"55B7", :ChromaSitingHorz},
           {"55B8", :ChromaSitingVert},
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
           #               # Colour
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
           #         # Chapters
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
           {"1549A966", :Info},
           # \Segment\Info
           {"2AD7B1", :TimecodeScale},
           {"7BA9", :Title},
           {"4D80", :MuxingApp},
           {"5741", :WritingApp},
           {"4489", :Duration},
           {"4461", :DateUTC},
           {"114D9B74", :SeekHead},
           # \Segment\SeekHead
           {"4DBB", :Seek},
           # \Segment\SeekHead\Seek
           {"53AC", :SeekPosition},
           {"53AB", :SeekID}
         ])

  @element_info %{
    EBML: %{type: :master},
    EBMLVersion: %{type: :uint},
    EBMLReadVersion: %{type: :uint},
    EBMLMaxIDLength: %{type: :uint},
    EBMLMaxSizeLength: %{type: :uint},
    DocType: %{type: :string},
    DocTypeVersion: %{type: :uint},
    DocTypeReadVersion: %{type: :uint},
    DocTypeExtension: %{type: :master},
    DocTypeExtensionName: %{type: :string},
    DocTypeExtensionVersion: %{type: :uint},
    CRC_32: %{type: :crc_32},
    Void: %{type: :void},
    Segment: %{type: :master},
    Cues: %{type: :master},
    CuePoint: %{type: :master},
    CueTime: %{type: :uint},
    CueTrackPositions: %{type: :master},
    CueRelativePosition: %{type: :uint},
    CueClusterPosition: %{type: :uint},
    CueTrack: %{type: :uint},
    CueDuration: %{type: :unit},
    CueBlockNumber: %{type: :uint},
    Cluster: %{type: :master},
    SimpleBlock: %{type: :binary},
    Timecode: %{type: :uint},
    PrevSize: %{type: :uint},
    BlockGroup: %{type: :master},
    Block: %{type: :binary},
    BlockAdditions: %{type: :master},
    BlockMore: %{type: :master},
    BlockAddID: %{type: :uint},
    BlockAdditional: %{type: :binary},
    BlockDuration: %{type: :uint},
    ReferenceBlock: %{type: :integer},
    DiscardPadding: %{type: :integer},
    Tags: %{type: :master},
    Tag: %{type: :master},
    Targets: %{type: :master},
    TargetTypeValue: %{type: :uint},
    TargetType: %{type: :string},
    TagTrackUID: %{type: :uint},
    SimpleTag: %{type: :master},
    TagString: %{type: :utf_8},
    TagName: %{type: :utf_8},
    TagLanguage: %{type: :string},
    TagDefault: %{type: :uint},
    TagBinary: %{type: :binary},
    Tracks: %{type: :master},
    TrackEntry: %{type: :master},
    TrackNumber: %{type: :uint},
    TrackUID: %{type: :uint},
    FlagEnabled: %{type: :unit},
    FlagDefault: %{type: :uint},
    FlagForced: %{type: :uint},
    FlagLacing: %{type: :uint},
    Language: %{type: :string},
    CodecID: %{type: :string},
    CodecDelay: %{type: :uint},
    SeekPreRoll: %{type: :uint},
    Name: %{type: :utf_8},
    TrackType: %{type: :uint},
    CodecPrivate: %{type: :binary},
    CodecName: %{type: :utf_8},
    Audio: %{type: :master},
    DefaultDuration: %{type: :uint},
    Channels: %{type: :uint},
    SamplingFrequency: %{type: :float},
    BitDepth: %{type: :uint},
    Video: %{type: :master},
    PixelWidth: %{type: :uint},
    PixelHeight: %{type: :uint},
    FlagInterlaced: %{type: :uint},
    Colour: %{type: :master},
    ChromaSitingHorz: %{type: :uint},
    ChromaSitingVert: %{type: :uint},
    Info: %{type: :master},
    TimecodeScale: %{type: :uint},
    Title: %{type: :utf_8},
    MuxingApp: %{type: :utf_8},
    WritingApp: %{type: :utf_8},
    Duration: %{type: :float},
    DateUTC: %{type: :date},
    SeekHead: %{type: :master},
    Seek: %{type: :master},
    SeekPosition: %{type: :uint},
    SeekID: %{type: :binary},
    Unknown: %{type: :unknown}
  }

  def element_type(name) do
    @element_info[name].type
  end

  def element_id_to_name(element_id) do
    case BiMap.fetch(@bimap, element_id) do
      {:ok, name} -> name
      :error -> :Unknown
    end
  end

  def name_to_element_id(name) do
    BiMap.fetch_key!(@bimap, name)
  end
end
