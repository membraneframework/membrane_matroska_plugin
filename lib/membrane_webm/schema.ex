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

  alias Membrane.WebM.Parser.EBML

  @bimap BiMap.new([
           ### EBML elements
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
           ### Matroska elements
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
    EBML: :master,
    EBMLVersion: :uint,
    EBMLReadVersion: :uint,
    EBMLMaxIDLength: :uint,
    EBMLMaxSizeLength: :uint,
    DocType: :string,
    DocTypeVersion: :uint,
    DocTypeReadVersion: :uint,
    DocTypeExtension: :master,
    DocTypeExtensionName: :string,
    DocTypeExtensionVersion: :uint,
    CRC_32: :crc_32,
    Void: :void,
    Segment: :master,
    Cues: :master,
    CuePoint: :master,
    CueTime: :uint,
    CueTrackPositions: :master,
    CueRelativePosition: :uint,
    CueClusterPosition: :uint,
    CueTrack: :uint,
    CueDuration: :unit,
    CueBlockNumber: :uint,
    Cluster: :master,
    SimpleBlock: :binary,
    Timecode: :uint,
    PrevSize: :uint,
    BlockGroup: :master,
    Block: :binary,
    BlockAdditions: :master,
    BlockMore: :master,
    BlockAddID: :uint,
    BlockAdditional: :binary,
    BlockDuration: :uint,
    ReferenceBlock: :integer,
    DiscardPadding: :integer,
    Tags: :master,
    Tag: :master,
    Targets: :master,
    TargetTypeValue: :uint,
    TargetType: :string,
    TagTrackUID: :uint,
    SimpleTag: :master,
    TagString: :utf_8,
    TagName: :utf_8,
    TagLanguage: :string,
    TagDefault: :uint,
    TagBinary: :binary,
    Tracks: :master,
    TrackEntry: :master,
    TrackNumber: :uint,
    TrackUID: :uint,
    FlagEnabled: :unit,
    FlagDefault: :uint,
    FlagForced: :uint,
    FlagLacing: :uint,
    Language: :string,
    CodecID: :string,
    CodecDelay: :uint,
    SeekPreRoll: :uint,
    Name: :utf_8,
    TrackType: :uint,
    CodecPrivate: :binary,
    CodecName: :utf_8,
    Audio: :master,
    DefaultDuration: :uint,
    Video: :master,
    PixelWidth: :uint,
    PixelHeight: :uint,
    FlagInterlaced: :uint,
    StereoMode: :uint,
    Colour: :master,
    ChromaSitingHorz: :uint,
    ChromaSitingVert: :uint,
    AlphaMode: :uint,
    PixelCropBottom: :uint,
    PixelCropTop: :uint,
    PixelCropLeft: :uint,
    PixelCropRight: :uint,
    DisplayWidth: :uint,
    DisplayHeight: :uint,
    DisplayUnit: :uint,
    AspectRatioType: :uint,
    SamplingFrequency: :float,
    OutputSamplingFrequency: :float,
    Channels: :uint,
    BitDepth: :uint,
    ContentEncoding: :master,
    ContentEncodingOrder: :uint,
    ContentEncodingScope: :uint,
    ContentEncodingType: :uint,
    ContentEncryption: :master,
    ContentEncAlgo: :uint,
    ContentEncKeyID: :binary,
    ContentEncAESSettings: :master,
    MatrixCoefficients: :uint,
    BitsPerChannel: :uint,
    ChromaSubsamplingHorz: :uint,
    ChromaSubsamplingVert: :uint,
    CbSubsamplingHorz: :uint,
    CbSubsamplingVert: :uint,
    Range: :uint,
    TransferCharacteristics: :uint,
    Primaries: :uint,
    MaxCLL: :uint,
    MaxFALL: :uint,
    MasteringMetadata: :master,
    PrimaryRChromaticityX: :float,
    PrimaryRChromaticityY: :float,
    PrimaryGChromaticityX: :float,
    PrimaryGChromaticityY: :float,
    PrimaryBChromaticityX: :float,
    PrimaryBChromaticityY: :float,
    WhitePointChromaticityX: :float,
    WhitePointChromaticityY: :float,
    LuminanceMax: :float,
    LuminanceMin: :float,
    Chapters: :master,
    EditionEntry: :master,
    ChapterAtom: :master,
    ChapterUID: :uint,
    ChapterStringUID: :utf_8,
    ChapterTimeStart: :uint,
    ChapterTimeEnd: :uint,
    ChapterDisplay: :master,
    ChapString: :utf_8,
    ChapLanguage: :string,
    ChapCountry: :string,
    AESSettingsCipherMode: :uint,
    Info: :master,
    TimestampScale: :uint,
    Title: :utf_8,
    MuxingApp: :utf_8,
    WritingApp: :utf_8,
    Duration: :float,
    DateUTC: :date,
    SeekHead: :master,
    Seek: :master,
    SeekPosition: :uint,
    SeekID: :binary,
    Unknown: :unknown
  }

  @spec element_type(atom) :: EBML.t()
  def element_type(name) do
    @element_info[name]
  end

  @spec element_id_to_name(integer) :: atom
  def element_id_to_name(element_id) do
    case BiMap.fetch(@bimap, element_id) do
      {:ok, name} -> name
      :error -> :Unknown
    end
  end

  @spec name_to_element_id(atom) :: integer
  def name_to_element_id(name) do
    BiMap.fetch_key!(@bimap, name)
  end
end
