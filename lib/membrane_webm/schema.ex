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
           {0x1A45DFA3, :EBML},
           {0x4286, :EBMLVersion},
           {0x42F7, :EBMLReadVersion},
           {0x42F2, :EBMLMaxIDLength},
           {0x42F3, :EBMLMaxSizeLength},
           {0x4282, :DocType},
           {0x4287, :DocTypeVersion},
           {0x4285, :DocTypeReadVersion},
           {0x4281, :DocTypeExtension},
           {0x4283, :DocTypeExtensionName},
           {0x4284, :DocTypeExtensionVersion},
           {0xEC, :Void},
           ### Matroska elements:
           {0x18538067, :Segment},
           # \Segment
           {0x1C53BB6B, :Cues},
           # \Segment\Cues
           {0xBB, :CuePoint},
           # \Segment\Cues\CuePoint
           {0xB3, :CueTime},
           {0xB7, :CueTrackPositions},
           # \Segment\Cues\CuePoint\CueTrackPositions
           {0xF0, :CueRelativePosition},
           {0xF1, :CueClusterPosition},
           {0xF7, :CueTrack},
           {0xB2, :CueDuration},
           {0x5378, :CueBlockNumber},
           {0x1F43B675, :Cluster},
           # \Segment\Cluster
           {0xA3, :SimpleBlock},
           {0xE7, :Timecode},
           {0xAB, :PrevSize},
           {0xA0, :BlockGroup},
           # \Segment\Cluster\BlockGroup
           {0xA1, :Block},
           {0x75A1, :BlockAdditions},
           # \Segment\Cluster\BlockGroup
           {0xA6, :BlockMore},
           # \Segment\Cluster\BlockGroup\BlockMore
           {0xEE, :BlockAddID},
           {0xA5, :BlockAdditional},
           {0x9B, :BlockDuration},
           {0xFB, :ReferenceBlock},
           {0x75A2, :DiscardPadding},
           {0x1254C367, :Tags},
           # \Segment\Tags
           {0x7373, :Tag},
           # \Segment\Tags\Tag
           {0x63C0, :Targets},
           # \Segment\Tags\Tag\Targets
           {0x68CA, :TargetTypeValue},
           {0x63CA, :TargetType},
           {0x63C5, :TagTrackUID},
           {0x67C8, :SimpleTag},
           # \Segment\Tags\Tag\SimpleTag
           {0x4487, :TagString},
           {0x45A3, :TagName},
           {0x447A, :TagLanguage},
           {0x4484, :TagDefault},
           {0x4485, :TagBinary},
           {0x1654AE6B, :Tracks},
           # \Segment\Tracks
           {0xAE, :TrackEntry},
           # \Segment\Tracks\TrackEntry
           {0xD7, :TrackNumber},
           {0x73C5, :TrackUID},
           {0xB9, :FlagEnabled},
           {0x88, :FlagDefault},
           {0x55AA, :FlagForced},
           {0x9C, :FlagLacing},
           {0x22B59C, :Language},
           {0x86, :CodecID},
           {0x56AA, :CodecDelay},
           {0x56BB, :SeekPreRoll},
           {0x536E, :Name},
           {0x83, :TrackType},
           {0x63A2, :CodecPrivate},
           {0x258688, :CodecName},
           {0xE1, :Audio},
           {0x23E383, :DefaultDuration},
           # \Segment\Tracks\TrackEntry\Audio
           {0x9F, :Channels},
           {0xB5, :SamplingFrequency},
           {0x6264, :BitDepth},
           {0xE0, :Video},
           # \Segment\Tracks\TrackEntry\Video
           {0xB0, :PixelWidth},
           {0xBA, :PixelHeight},
           {0x9A, :FlagInterlaced},
           {0x53B8, :StereoMode},
           {0x55B0, :Colour},
           # \Segment\Tracks\TrackEntry\Video\Colour
           {0x55B7, :ChromaSitingHorz},
           {0x55B8, :ChromaSitingVert},
           {0x53C0, :AlphaMode},
           {0x54AA, :PixelCropBottom},
           {0x54BB, :PixelCropTop},
           {0x54CC, :PixelCropLeft},
           {0x54DD, :PixelCropRight},
           {0x54B0, :DisplayWidth},
           {0x54BA, :DisplayHeight},
           {0x54B2, :DisplayUnit},
           {0x54B3, :AspectRatioType},
           {0xE1, :Audio},
           {0xB5, :SamplingFrequency},
           {0x78B5, :OutputSamplingFrequency},
           {0x9F, :Channels},
           {0x6264, :BitDepth},
           {0x6240, :ContentEncoding},
           {0x5031, :ContentEncodingOrder},
           {0x5032, :ContentEncodingScope},
           {0x5033, :ContentEncodingType},
           {0x5035, :ContentEncryption},
           {0x47E1, :ContentEncAlgo},
           {0x47E2, :ContentEncKeyID},
           {0x47E7, :ContentEncAESSettings},
           {0x47E8, :AESSettingsCipherMode},
           {0x55B1, :MatrixCoefficients},
           {0x55B2, :BitsPerChannel},
           {0x55B3, :ChromaSubsamplingHorz},
           {0x55B4, :ChromaSubsamplingVert},
           {0x55B5, :CbSubsamplingHorz},
           {0x55B6, :CbSubsamplingVert},
           {0x55B9, :Range},
           {0x55BA, :TransferCharacteristics},
           {0x55BB, :Primaries},
           {0x55BC, :MaxCLL},
           {0x55BD, :MaxFALL},
           {0x55D0, :MasteringMetadata},
           {0x55D1, :PrimaryRChromaticityX},
           {0x55D2, :PrimaryRChromaticityY},
           {0x55D3, :PrimaryGChromaticityX},
           {0x55D4, :PrimaryGChromaticityY},
           {0x55D5, :PrimaryBChromaticityX},
           {0x55D6, :PrimaryBChromaticityY},
           {0x55D7, :WhitePointChromaticityX},
           {0x55D8, :WhitePointChromaticityY},
           {0x55D9, :LuminanceMax},
           {0x55DA, :LuminanceMin},
           # Chapters
           {0x1043A770, :Chapters},
           {0x45B9, :EditionEntry},
           {0xB6, :ChapterAtom},
           {0x73C4, :ChapterUID},
           {0x5654, :ChapterStringUID},
           {0x91, :ChapterTimeStart},
           {0x92, :ChapterTimeEnd},
           {0x80, :ChapterDisplay},
           {0x85, :ChapString},
           {0x437C, :ChapLanguage},
           {0x437E, :ChapCountry},
           {0x1549A966, :Info},
           # \Segment\Info
           {0x2AD7B1, :TimestampScale},
           {0x7BA9, :Title},
           {0x4D80, :MuxingApp},
           {0x5741, :WritingApp},
           {0x4489, :Duration},
           {0x4461, :DateUTC},
           {0x114D9B74, :SeekHead},
           # \Segment\SeekHead
           {0x4DBB, :Seek},
           # \Segment\SeekHead\Seek
           {0x53AC, :SeekPosition},
           {0x53AB, :SeekID}
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
    StereoMode: %{type: :uint},
    Colour: %{type: :master},
    ChromaSitingHorz: %{type: :uint},
    ChromaSitingVert: %{type: :uint},
    AlphaMode: %{type: :uint},
    PixelCropBottom: %{type: :uint},
    PixelCropTop: %{type: :uint},
    PixelCropLeft: %{type: :uint},
    PixelCropRight: %{type: :uint},
    DisplayWidth: %{type: :uint},
    DisplayHeight: %{type: :uint},
    DisplayUnit: %{type: :uint},
    AspectRatioType: %{type: :uint},
    SamplingFrequency: %{type: :float},
    OutputSamplingFrequency: %{type: :float},
    Channels: %{type: :uint},
    BitDepth: %{type: :uint},
    ContentEncoding: %{type: :master},
    ContentEncodingOrder: %{type: :uint},
    ContentEncodingScope: %{type: :uint},
    ContentEncodingType: %{type: :uint},
    ContentEncryption: %{type: :master},
    ContentEncAlgo: %{type: :uint},
    ContentEncKeyID: %{type: :binary},
    ContentEncAESSettings: %{type: :master},
    MatrixCoefficients: %{type: :uint},
    BitsPerChannel: %{type: :uint},
    ChromaSubsamplingHorz: %{type: :uint},
    ChromaSubsamplingVert: %{type: :uint},
    CbSubsamplingHorz: %{type: :uint},
    CbSubsamplingVert: %{type: :uint},
    Range: %{type: :uint},
    TransferCharacteristics: %{type: :uint},
    Primaries: %{type: :uint},
    MaxCLL: %{type: :uint},
    MaxFALL: %{type: :uint},
    MasteringMetadata: %{type: :master},
    PrimaryRChromaticityX: %{type: :float},
    PrimaryRChromaticityY: %{type: :float},
    PrimaryGChromaticityX: %{type: :float},
    PrimaryGChromaticityY: %{type: :float},
    PrimaryBChromaticityX: %{type: :float},
    PrimaryBChromaticityY: %{type: :float},
    WhitePointChromaticityX: %{type: :float},
    WhitePointChromaticityY: %{type: :float},
    LuminanceMax: %{type: :float},
    LuminanceMin: %{type: :float},
    Chapters: %{type: :master},
    EditionEntry: %{type: :master},
    ChapterAtom: %{type: :master},
    ChapterUID: %{type: :uint},
    ChapterStringUID: %{type: :utf_8},
    ChapterTimeStart: %{type: :uint},
    ChapterTimeEnd: %{type: :uint},
    ChapterDisplay: %{type: :master},
    ChapString: %{type: :utf_8},
    ChapLanguage: %{type: :string},
    ChapCountry: %{type: :string},
    AESSettingsCipherMode: %{type: :uint},
    Info: %{type: :master},
    TimestampScale: %{type: :uint},
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
