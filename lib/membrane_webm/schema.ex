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
           {"53B8", :StereoMode},
           {"55B0", :Colour},
           # \Segment\Tracks\TrackEntry\Video\Colour
           {"55B7", :ChromaSitingHorz},
           {"55B8", :ChromaSitingVert},
           {"53C0", :AlphaMode},
           {"54AA", :PixelCropBottom},
           {"54BB", :PixelCropTop},
           {"54CC", :PixelCropLeft},
           {"54DD", :PixelCropRight},
           {"54B0", :DisplayWidth},
           {"54BA", :DisplayHeight},
           {"54B2", :DisplayUnit},
           {"54B3", :AspectRatioType},
           {"E1", :Audio},
           {"B5", :SamplingFrequency},
           {"78B5", :OutputSamplingFrequency},
           {"9F", :Channels},
           {"6264", :BitDepth},
           {"6240", :ContentEncoding},
           {"5031", :ContentEncodingOrder},
           {"5032", :ContentEncodingScope},
           {"5033", :ContentEncodingType},
           {"5035", :ContentEncryption},
           {"47E1", :ContentEncAlgo},
           {"47E2", :ContentEncKeyID},
           {"47E7", :ContentEncAESSettings},
           {"47E8", :AESSettingsCipherMode},
           {"55B1", :MatrixCoefficients},
           {"55B2", :BitsPerChannel},
           {"55B3", :ChromaSubsamplingHorz},
           {"55B4", :ChromaSubsamplingVert},
           {"55B5", :CbSubsamplingHorz},
           {"55B6", :CbSubsamplingVert},
           {"55B9", :Range},
           {"55BA", :TransferCharacteristics},
           {"55BB", :Primaries},
           {"55BC", :MaxCLL},
           {"55BD", :MaxFALL},
           {"55D0", :MasteringMetadata},
           {"55D1", :PrimaryRChromaticityX},
           {"55D2", :PrimaryRChromaticityY},
           {"55D3", :PrimaryGChromaticityX},
           {"55D4", :PrimaryGChromaticityY},
           {"55D5", :PrimaryBChromaticityX},
           {"55D6", :PrimaryBChromaticityY},
           {"55D7", :WhitePointChromaticityX},
           {"55D8", :WhitePointChromaticityY},
           {"55D9", :LuminanceMax},
           {"55DA", :LuminanceMin},
           # Chapters
           {"1043A770", :Chapters},
           {"45B9", :EditionEntry},
           {"B6", :ChapterAtom},
           {"73C4", :ChapterUID},
           {"5654", :ChapterStringUID},
           {"91", :ChapterTimeStart},
           {"92", :ChapterTimeEnd},
           {"80", :ChapterDisplay},
           {"85", :ChapString},
           {"437C", :ChapLanguage},
           {"437E", :ChapCountry},
           {"1549A966", :Info},
           # \Segment\Info
           {"2AD7B1", :TimestampScale},
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
