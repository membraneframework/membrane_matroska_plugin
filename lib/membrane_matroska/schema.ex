defmodule Membrane.Matroska.Schema do
  @moduledoc """
  Matroska structure schema for muxing and demuxing

  Docs:
    - EBML https://datatracker.ietf.org/doc/html/rfc8794
    - Matroska https://matroska.org/technical/basics.html

  Matroska elements and ID's https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-10.html#name-matroska-schema
  Matroska supported Matroska elements https://www.matroskaproject.org/docs/container/#EBML
  """

  # A typical Matroska file has the following structure:

  # EBML
  # Segment
  # ├── SeekHead
  # │   ├── Seek
  # │   ├── Seek
  # │   ├── Seek
  # │   └── Seek
  # ├── Void
  # ├── Info
  # ├── Tracks
  # │   └── TrackEntry
  # │       └── Video
  # │           └── Colour
  # ├── Cues
  # │   ├── CuePoint
  # │   │   └── CueTrackPositions
  # │   ├── CuePoint
  # │   │   └── CueTrackPositions
  # │   ├── CuePoint
  # │   │   └── CueTrackPositions
  # ...
  # ├── Cluster
  # │   ├── SimpleBlock
  # │   ├── SimpleBlock
  # │   ├── SimpleBlock
  # │   ├── SimpleBlock
  # │   └── SimpleBlock
  # ├── Cluster
  # │   ├── SimpleBlock
  # │   ├── SimpleBlock
  # │   ├── SimpleBlock
  # │   ├── SimpleBlock
  # │   └── SimpleBlock

  alias Membrane.Matroska.Parser
  alias Membrane.Matroska.Parser.EBML
  alias Membrane.Matroska.Serializer

  @element_id_to_name BiMap.new([
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
                        {0xBF, :CRC_32},

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
                        {0xEA, :CueCodecState},
                        {0xDB, :CueReference},
                        {0x96, :CueRefTime},
                        {0x97, :CueRefCluster},
                        {0x535F, :CueRefNumber},
                        {0xEB, :CueRefCodecState},
                        {0x1F43B675, :Cluster},
                        {0xA4, :BlockGroupCodecState},
                        # \Segment\Cluster
                        {0xA3, :SimpleBlock},
                        {0xE7, :Timecode},
                        {0xAB, :PrevSize},
                        {0xA0, :BlockGroup},
                        {0xA7, :Position},
                        {0x5854, :SilentTracks},
                        {0xAF, :EncryptedBlock},
                        #  \Segment\Cluster\Silenttracks
                        {0x58D7, :SilentTrackNumber},
                        # \Segment\Cluster\BlockGroup
                        {0xA1, :Block},
                        {0x75A1, :BlockAdditions},
                        {0xA6, :BlockMore},
                        # Depracated {0xA2,:BlockVirtual},
                        {0xFA, :ReferencePriority},
                        {0xFD, :ReferenceVirtual},
                        {0xC8, :ReferenceFrame},
                        {0x8E, :Slices},
                        # \Segment\Cluster\BlockGroup\BlockMore
                        {0xEE, :BlockAddID},
                        {0xA5, :BlockAdditional},
                        {0x9B, :BlockDuration},
                        {0xFB, :ReferenceBlock},
                        {0x75A2, :DiscardPadding},
                        {0x1254C367, :Tags},
                        # \Segment\Cluster\BlockGroup\Slices
                        # Depracated {0xE8,:TimeSlice},
                        # \Segment\Cluster\BlockGroup\Slices\TimeSlice
                        # Depracated {0xCC,:LaceNumber},
                        {0xCD, :FrameNumber},
                        {0xCB, :BlockAdditionID},
                        {0xCE, :Delay},
                        {0xCF, :SliceDuration},
                        # \Segment\Cluster\BlockGroup\ReferenceFrame
                        {0xC9, :ReferenceOffset},
                        {0xCA, :ReferenceTimestamp},
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
                        {0xE0, :Video},
                        {0x23E383, :DefaultDuration},
                        {0x6DE7, :MinCache},
                        {0x6DF8, :MaxCache},
                        {0x234E7A, :DefaultDecodedFieldDuration},
                        {0x537F, :TrackOffset},
                        {0x55EE, :MaxBlockAdditionID},
                        {0x7446, :AttachmentLink},
                        {0x3A9697, :CodecSettings},
                        {0x3B4040, :CodecInfoURL},
                        {0x26B240, :CodecDownloadURL},
                        {0xAA, :CodecDecodeAll},
                        # Depracated {0x53B9,:OldStereoMode},
                        {0x6FAB, :TrackOverlay},
                        {0x6624, :TrackTranslate},

                        # \Segment\Tracks\TrackEntry\Audio
                        {0x9F, :Channels},
                        {0xB5, :SamplingFrequency},
                        {0x6264, :BitDepth},
                        {0x7D7B, :ChannelPositions},

                        # \Segment\Tracks\TrackEntry\Video
                        {0xB0, :PixelWidth},
                        {0xBA, :PixelHeight},
                        {0x9A, :FlagInterlaced},
                        {0x53B8, :StereoMode},
                        {0x55B0, :Colour},
                        {0x2FB523, :GammaValue},
                        {0x2EB524, :ColourSpace},
                        # Depracated  {0x2383E3, :FrameRate},
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
                        {0x5034, :ContentCompression},
                        {0x4254, :ContentCompAlgo},
                        {0x4255, :ContentCompSettings},
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
                        # \Segment\Tracks\TrackEntry\TrackTranslate
                        {0x66A5, :TrackTranslateTrackID},
                        {0x66BF, :TrackTranszlateCodec},
                        {0x66FC, :TrackTranslateEditionUID},
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
                        {0x45BC, :EditionUID},
                        {0x45DB, :EditionFlagDefault},
                        {0x45DD, :EditionFlagOrdered},
                        {0x1549A966, :Info},
                        # \Segment\Info
                        {0x2AD7B1, :TimestampScale},
                        {0x7BA9, :Title},
                        {0x4D80, :MuxingApp},
                        {0x5741, :WritingApp},
                        {0x4489, :Duration},
                        {0x4461, :DateUTC},
                        {0x114D9B74, :SeekHead},
                        {0x73A4, :SegmentUID},
                        {0x7384, :SegmentFilename},
                        {0x3CB923, :PrevUID},
                        {0x3C83AB, :PrevFilename},
                        {0x3EB923, :NextUID},
                        {0x3E83BB, :NextFilename},
                        {0x4444, :SegmentFamily},
                        {0x6924, :ChapterTranslate},
                        {0x69A5, :ChapterTranslateID},
                        {0x69BF, :ChapterTranslateCodec},
                        {0x69FC, :ChapterTranslateEditionUID},

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
    Void: :binary,
    Segment: :master,
    Cues: :master,
    CuePoint: :master,
    CueTime: :uint,
    CueTrackPositions: :master,
    CueRelativePosition: :uint,
    CueClusterPosition: :uint,
    CueTrack: :uint,
    CueDuration: :uint,
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
    FlagEnabled: :uint,
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

  @matroska_deserializer_schema %{
    EBML: &Parser.EBML.parse_master/2,
    EBMLVersion: &Parser.EBML.parse_uint/1,
    EBMLReadVersion: &Parser.EBML.parse_uint/1,
    EBMLMaxIDLength: &Parser.EBML.parse_uint/1,
    EBMLMaxSizeLength: &Parser.EBML.parse_uint/1,
    DocType: &Parser.Matroska.parse_doc_type/1,
    DocTypeVersion: &Parser.EBML.parse_uint/1,
    DocTypeReadVersion: &Parser.EBML.parse_uint/1,
    DocTypeExtension: &Parser.EBML.parse_master/2,
    DocTypeExtensionName: &Parser.EBML.parse_string/1,
    DocTypeExtensionVersion: &Parser.EBML.parse_uint/1,
    # CRC_32: :crc_32,
    Void: &Parser.EBML.parse_binary/1,
    Segment: :ApplyFlatParsing,
    Cues: &Parser.EBML.parse_master/2,
    CuePoint: &Parser.EBML.parse_master/2,
    CueTime: &Parser.EBML.parse_uint/1,
    CueTrackPositions: &Parser.EBML.parse_master/2,
    CueRelativePosition: &Parser.EBML.parse_uint/1,
    CueClusterPosition: &Parser.EBML.parse_uint/1,
    CueTrack: &Parser.EBML.parse_uint/1,
    CueDuration: &Parser.EBML.parse_uint/1,
    CueBlockNumber: &Parser.EBML.parse_uint/1,
    Cluster: :ApplyFlatParsing,
    SimpleBlock: &Parser.Matroska.parse_simple_block/1,
    Timecode: &Parser.EBML.parse_uint/1,
    PrevSize: &Parser.EBML.parse_uint/1,
    BlockGroup: &Parser.EBML.parse_master/2,
    Block: &Parser.Matroska.parse_block/1,
    BlockAdditions: &Parser.EBML.parse_master/2,
    BlockMore: &Parser.EBML.parse_master/2,
    BlockAddID: &Parser.EBML.parse_uint/1,
    BlockAdditional: &Parser.EBML.parse_binary/1,
    BlockDuration: &Parser.EBML.parse_uint/1,
    ReferenceBlock: &Parser.EBML.parse_integer/1,
    DiscardPadding: &Parser.EBML.parse_integer/1,
    Tags: &Parser.EBML.parse_master/2,
    Tag: &Parser.EBML.parse_master/2,
    Targets: &Parser.EBML.parse_master/2,
    TargetTypeValue: &Parser.EBML.parse_uint/1,
    TargetType: &Parser.EBML.parse_string/1,
    TagTrackUID: &Parser.EBML.parse_uint/1,
    SimpleTag: &Parser.EBML.parse_master/2,
    TagString: &Parser.EBML.parse_utf8/1,
    TagName: &Parser.EBML.parse_utf8/1,
    TagLanguage: &Parser.EBML.parse_string/1,
    TagDefault: &Parser.EBML.parse_uint/1,
    TagBinary: &Parser.EBML.parse_binary/1,
    Tracks: &Parser.EBML.parse_master/2,
    TrackEntry: &Parser.EBML.parse_master/2,
    TrackNumber: &Parser.EBML.parse_uint/1,
    TrackUID: &Parser.EBML.parse_uint/1,
    FlagEnabled: &Parser.EBML.parse_uint/1,
    FlagDefault: &Parser.EBML.parse_uint/1,
    FlagForced: &Parser.EBML.parse_uint/1,
    FlagLacing: &Parser.EBML.parse_uint/1,
    Language: &Parser.EBML.parse_string/1,
    CodecID: &Parser.Matroska.parse_codec_id/1,
    CodecDelay: &Parser.EBML.parse_uint/1,
    SeekPreRoll: &Parser.EBML.parse_uint/1,
    Name: &Parser.EBML.parse_utf8/1,
    TrackType: &Parser.Matroska.parse_track_type/1,
    CodecPrivate: &Parser.EBML.parse_binary/1,
    CodecName: &Parser.EBML.parse_utf8/1,
    Audio: &Parser.EBML.parse_master/2,
    DefaultDuration: &Parser.EBML.parse_uint/1,
    Video: &Parser.EBML.parse_master/2,
    PixelWidth: &Parser.EBML.parse_uint/1,
    PixelHeight: &Parser.EBML.parse_uint/1,
    FlagInterlaced: &Parser.Matroska.parse_flag_interlaced/1,
    StereoMode: &Parser.Matroska.parse_stereo_mode/1,
    Colour: &Parser.EBML.parse_master/2,
    ChromaSitingHorz: &Parser.Matroska.parse_chroma_siting_horz/1,
    ChromaSitingVert: &Parser.Matroska.parse_chroma_siting_vert/1,
    AlphaMode: &Parser.EBML.parse_uint/1,
    PixelCropBottom: &Parser.EBML.parse_uint/1,
    PixelCropTop: &Parser.EBML.parse_uint/1,
    PixelCropLeft: &Parser.EBML.parse_uint/1,
    PixelCropRight: &Parser.EBML.parse_uint/1,
    DisplayWidth: &Parser.EBML.parse_uint/1,
    DisplayHeight: &Parser.EBML.parse_uint/1,
    DisplayUnit: &Parser.EBML.parse_uint/1,
    AspectRatioType: &Parser.EBML.parse_uint/1,
    SamplingFrequency: &Parser.EBML.parse_float/1,
    OutputSamplingFrequency: &Parser.EBML.parse_float/1,
    Channels: &Parser.EBML.parse_uint/1,
    BitDepth: &Parser.EBML.parse_uint/1,
    ContentEncoding: &Parser.EBML.parse_master/2,
    ContentEncodingOrder: &Parser.EBML.parse_uint/1,
    ContentEncodingScope: &Parser.EBML.parse_uint/1,
    ContentEncodingType: &Parser.EBML.parse_uint/1,
    ContentEncryption: &Parser.EBML.parse_master/2,
    ContentEncAlgo: &Parser.EBML.parse_uint/1,
    ContentEncKeyID: &Parser.EBML.parse_binary/1,
    ContentEncAESSettings: &Parser.EBML.parse_master/2,
    MatrixCoefficients: &Parser.EBML.parse_uint/1,
    BitsPerChannel: &Parser.EBML.parse_uint/1,
    ChromaSubsamplingHorz: &Parser.EBML.parse_uint/1,
    ChromaSubsamplingVert: &Parser.EBML.parse_uint/1,
    CbSubsamplingHorz: &Parser.EBML.parse_uint/1,
    CbSubsamplingVert: &Parser.EBML.parse_uint/1,
    Range: &Parser.EBML.parse_uint/1,
    TransferCharacteristics: &Parser.EBML.parse_uint/1,
    Primaries: &Parser.EBML.parse_uint/1,
    MaxCLL: &Parser.EBML.parse_uint/1,
    MaxFALL: &Parser.EBML.parse_uint/1,
    MasteringMetadata: &Parser.EBML.parse_master/2,
    PrimaryRChromaticityX: &Parser.EBML.parse_float/1,
    PrimaryRChromaticityY: &Parser.EBML.parse_float/1,
    PrimaryGChromaticityX: &Parser.EBML.parse_float/1,
    PrimaryGChromaticityY: &Parser.EBML.parse_float/1,
    PrimaryBChromaticityX: &Parser.EBML.parse_float/1,
    PrimaryBChromaticityY: &Parser.EBML.parse_float/1,
    WhitePointChromaticityX: &Parser.EBML.parse_float/1,
    WhitePointChromaticityY: &Parser.EBML.parse_float/1,
    LuminanceMax: &Parser.EBML.parse_float/1,
    LuminanceMin: &Parser.EBML.parse_float/1,
    Chapters: &Parser.EBML.parse_master/2,
    EditionEntry: &Parser.EBML.parse_master/2,
    ChapterAtom: &Parser.EBML.parse_master/2,
    ChapterUID: &Parser.EBML.parse_uint/1,
    ChapterStringUID: &Parser.EBML.parse_utf8/1,
    ChapterTimeStart: &Parser.EBML.parse_uint/1,
    ChapterTimeEnd: &Parser.EBML.parse_uint/1,
    ChapterDisplay: &Parser.EBML.parse_master/2,
    ChapString: &Parser.EBML.parse_utf8/1,
    ChapLanguage: &Parser.EBML.parse_string/1,
    ChapCountry: &Parser.EBML.parse_string/1,
    AESSettingsCipherMode: &Parser.EBML.parse_uint/1,
    Info: &Parser.EBML.parse_master/2,
    TimestampScale: &Parser.EBML.parse_uint/1,
    Title: &Parser.EBML.parse_utf8/1,
    MuxingApp: &Parser.EBML.parse_utf8/1,
    WritingApp: &Parser.EBML.parse_utf8/1,
    Duration: &Parser.EBML.parse_float/1,
    DateUTC: &Parser.EBML.parse_date/1,
    SeekHead: &Parser.EBML.parse_master/2,
    Seek: &Parser.EBML.parse_master/2,
    SeekPosition: &Parser.EBML.parse_uint/1,
    SeekID: &Parser.EBML.parse_binary/1,
    TrackOffset: &Parser.EBML.parse_uint/1,
    Unknown: &Parser.EBML.parse_binary/1
  }

  @matroska_serializer_schema %{
    EBML: &Serializer.EBML.serialize_master/3,
    EBMLVersion: &Serializer.EBML.serialize_uint/3,
    EBMLReadVersion: &Serializer.EBML.serialize_uint/3,
    EBMLMaxIDLength: &Serializer.EBML.serialize_uint/3,
    EBMLMaxSizeLength: &Serializer.EBML.serialize_uint/3,
    DocType: &Serializer.EBML.serialize_string/3,
    DocTypeVersion: &Serializer.EBML.serialize_uint/3,
    DocTypeReadVersion: &Serializer.EBML.serialize_uint/3,
    DocTypeExtension: &Serializer.EBML.serialize_master/3,
    DocTypeExtensionName: &Serializer.EBML.serialize_string/3,
    DocTypeExtensionVersion: &Serializer.EBML.serialize_uint/3,
    # CRC_32: :crc_32,
    Void: &Serializer.Matroska.serialize_void/3,
    Segment: &Serializer.EBML.serialize_master/3,
    Cues: &Serializer.EBML.serialize_master/3,
    CuePoint: &Serializer.EBML.serialize_master/3,
    CueTime: &Serializer.EBML.serialize_uint/3,
    CueTrackPositions: &Serializer.EBML.serialize_master/3,
    CueRelativePosition: &Serializer.EBML.serialize_uint/3,
    CueClusterPosition: &Serializer.EBML.serialize_uint/3,
    CueTrack: &Serializer.EBML.serialize_uint/3,
    CueDuration: &Serializer.EBML.serialize_uint/3,
    CueBlockNumber: &Serializer.EBML.serialize_uint/3,
    Cluster: &Serializer.Matroska.serialize_cluster/3,
    SimpleBlock: &Serializer.Matroska.serialize_simple_block/3,
    Timecode: &Serializer.EBML.serialize_uint/3,
    PrevSize: &Serializer.EBML.serialize_uint/3,
    BlockGroup: &Serializer.EBML.serialize_master/3,
    Block: &Serializer.EBML.serialize_binary/3,
    BlockAdditions: &Serializer.EBML.serialize_master/3,
    BlockMore: &Serializer.EBML.serialize_master/3,
    BlockAddID: &Serializer.EBML.serialize_uint/3,
    BlockAdditional: &Serializer.EBML.serialize_binary/3,
    BlockDuration: &Serializer.EBML.serialize_uint/3,
    ReferenceBlock: &Serializer.EBML.serialize_integer/3,
    DiscardPadding: &Serializer.EBML.serialize_integer/3,
    Tags: &Serializer.EBML.serialize_master/3,
    Tag: &Serializer.EBML.serialize_master/3,
    Targets: &Serializer.EBML.serialize_master/3,
    TargetTypeValue: &Serializer.EBML.serialize_uint/3,
    TargetType: &Serializer.EBML.serialize_string/3,
    TagTrackUID: &Serializer.EBML.serialize_uint/3,
    SimpleTag: &Serializer.EBML.serialize_master/3,
    TagString: &Serializer.EBML.serialize_utf8/3,
    TagName: &Serializer.EBML.serialize_utf8/3,
    TagLanguage: &Serializer.EBML.serialize_string/3,
    TagDefault: &Serializer.EBML.serialize_uint/3,
    TagBinary: &Serializer.EBML.serialize_binary/3,
    Tracks: &Serializer.EBML.serialize_master/3,
    TrackEntry: &Serializer.EBML.serialize_master/3,
    TrackNumber: &Serializer.EBML.serialize_uint/3,
    TrackUID: &Serializer.EBML.serialize_uint/3,
    FlagEnabled: &Serializer.EBML.serialize_uint/3,
    FlagDefault: &Serializer.EBML.serialize_uint/3,
    FlagForced: &Serializer.EBML.serialize_uint/3,
    FlagLacing: &Serializer.EBML.serialize_uint/3,
    Language: &Serializer.EBML.serialize_string/3,
    CodecID: &Serializer.EBML.serialize_string/3,
    CodecDelay: &Serializer.EBML.serialize_uint/3,
    SeekPreRoll: &Serializer.EBML.serialize_uint/3,
    Name: &Serializer.EBML.serialize_utf8/3,
    TrackType: &Serializer.EBML.serialize_uint/3,
    CodecPrivate: &Serializer.EBML.serialize_binary/3,
    CodecName: &Serializer.EBML.serialize_utf8/3,
    Audio: &Serializer.EBML.serialize_master/3,
    DefaultDuration: &Serializer.EBML.serialize_uint/3,
    Video: &Serializer.EBML.serialize_master/3,
    PixelWidth: &Serializer.EBML.serialize_uint/3,
    PixelHeight: &Serializer.EBML.serialize_uint/3,
    FlagInterlaced: &Serializer.EBML.serialize_uint/3,
    StereoMode: &Serializer.EBML.serialize_uint/3,
    Colour: &Serializer.EBML.serialize_master/3,
    ChromaSitingHorz: &Serializer.EBML.serialize_uint/3,
    ChromaSitingVert: &Serializer.EBML.serialize_uint/3,
    AlphaMode: &Serializer.EBML.serialize_uint/3,
    PixelCropBottom: &Serializer.EBML.serialize_uint/3,
    PixelCropTop: &Serializer.EBML.serialize_uint/3,
    PixelCropLeft: &Serializer.EBML.serialize_uint/3,
    PixelCropRight: &Serializer.EBML.serialize_uint/3,
    DisplayWidth: &Serializer.EBML.serialize_uint/3,
    DisplayHeight: &Serializer.EBML.serialize_uint/3,
    DisplayUnit: &Serializer.EBML.serialize_uint/3,
    AspectRatioType: &Serializer.EBML.serialize_uint/3,
    SamplingFrequency: &Serializer.EBML.serialize_float/3,
    OutputSamplingFrequency: &Serializer.EBML.serialize_float/3,
    Channels: &Serializer.EBML.serialize_uint/3,
    BitDepth: &Serializer.EBML.serialize_uint/3,
    ContentEncoding: &Serializer.EBML.serialize_master/3,
    ContentEncodingOrder: &Serializer.EBML.serialize_uint/3,
    ContentEncodingScope: &Serializer.EBML.serialize_uint/3,
    ContentEncodingType: &Serializer.EBML.serialize_uint/3,
    ContentEncryption: &Serializer.EBML.serialize_master/3,
    ContentEncAlgo: &Serializer.EBML.serialize_uint/3,
    ContentEncKeyID: &Serializer.EBML.serialize_binary/3,
    ContentEncAESSettings: &Serializer.EBML.serialize_master/3,
    MatrixCoefficients: &Serializer.EBML.serialize_uint/3,
    BitsPerChannel: &Serializer.EBML.serialize_uint/3,
    ChromaSubsamplingHorz: &Serializer.EBML.serialize_uint/3,
    ChromaSubsamplingVert: &Serializer.EBML.serialize_uint/3,
    CbSubsamplingHorz: &Serializer.EBML.serialize_uint/3,
    CbSubsamplingVert: &Serializer.EBML.serialize_uint/3,
    Range: &Serializer.EBML.serialize_uint/3,
    TransferCharacteristics: &Serializer.EBML.serialize_uint/3,
    Primaries: &Serializer.EBML.serialize_uint/3,
    MaxCLL: &Serializer.EBML.serialize_uint/3,
    MaxFALL: &Serializer.EBML.serialize_uint/3,
    MasteringMetadata: &Serializer.EBML.serialize_master/3,
    PrimaryRChromaticityX: &Serializer.EBML.serialize_float/3,
    PrimaryRChromaticityY: &Serializer.EBML.serialize_float/3,
    PrimaryGChromaticityX: &Serializer.EBML.serialize_float/3,
    PrimaryGChromaticityY: &Serializer.EBML.serialize_float/3,
    PrimaryBChromaticityX: &Serializer.EBML.serialize_float/3,
    PrimaryBChromaticityY: &Serializer.EBML.serialize_float/3,
    WhitePointChromaticityX: &Serializer.EBML.serialize_float/3,
    WhitePointChromaticityY: &Serializer.EBML.serialize_float/3,
    LuminanceMax: &Serializer.EBML.serialize_float/3,
    LuminanceMin: &Serializer.EBML.serialize_float/3,
    Chapters: &Serializer.EBML.serialize_master/3,
    EditionEntry: &Serializer.EBML.serialize_master/3,
    ChapterAtom: &Serializer.EBML.serialize_master/3,
    ChapterUID: &Serializer.EBML.serialize_uint/3,
    ChapterStringUID: &Serializer.EBML.serialize_utf8/3,
    ChapterTimeStart: &Serializer.EBML.serialize_uint/3,
    ChapterTimeEnd: &Serializer.EBML.serialize_uint/3,
    ChapterDisplay: &Serializer.EBML.serialize_master/3,
    ChapString: &Serializer.EBML.serialize_utf8/3,
    ChapLanguage: &Serializer.EBML.serialize_string/3,
    ChapCountry: &Serializer.EBML.serialize_string/3,
    AESSettingsCipherMode: &Serializer.EBML.serialize_uint/3,
    Info: &Serializer.EBML.serialize_master/3,
    TimestampScale: &Serializer.EBML.serialize_uint/3,
    Title: &Serializer.EBML.serialize_utf8/3,
    MuxingApp: &Serializer.EBML.serialize_utf8/3,
    WritingApp: &Serializer.EBML.serialize_utf8/3,
    Duration: &Serializer.EBML.serialize_float/3,
    DateUTC: &Serializer.EBML.serialize_date/3,
    SeekHead: &Serializer.EBML.serialize_master/3,
    Seek: &Serializer.EBML.serialize_master/3,
    SeekPosition: &Serializer.EBML.serialize_uint/3,
    SeekID: &Serializer.EBML.serialize_binary/3,
    TrackOffset: &Serializer.EBML.serialize_uint/3,
    Unknown: &Serializer.EBML.serialize_binary/3
  }

  for {name, function} <- @matroska_serializer_schema do
    defp fetch_serializer(unquote(name)), do: unquote(function)
  end

  defp fetch_serializer(_default), do: &Serializer.EBML.serialize_binary/3

  for {name, function} <- @matroska_deserializer_schema do
    defp fetch_deserializer(unquote(name)), do: unquote(function)
  end

  defp fetch_deserializer(_default), do: &Parser.EBML.parse_binary/1

  for {id, name} <- BiMap.to_list(@element_id_to_name) do
    defp fetch_element_name(unquote(id)), do: unquote(name)
    defp fetch_element_id(unquote(name)), do: unquote(id)
  end

  defp fetch_element_name(_default), do: :Unknown

  for {name, type} <- @element_info do
    defp fetch_element_info(unquote(name)), do: unquote(type)
  end

  @spec deserialize_matroska(atom) :: function
  def deserialize_matroska(name) do
    fetch_deserializer(name)
  end

  @spec serialize_matroska(atom) :: function
  def serialize_matroska(name) do
    fetch_serializer(name)
  end

  @spec element_type(atom) :: EBML.element_type_t()
  def element_type(name) do
    fetch_element_info(name)
  end

  @spec element_id_to_name(integer) :: atom
  def element_id_to_name(element_id) do
    fetch_element_name(element_id)
  end

  @spec name_to_element_id(atom) :: integer
  def name_to_element_id(name) do
    fetch_element_id(name)
  end
end
