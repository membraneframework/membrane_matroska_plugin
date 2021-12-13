defmodule Membrane.WebM.Muxer do
  @moduledoc """
  Module for muxing WebM files.

  """
  use Bitwise

  use Membrane.Filter

  alias Membrane.{Buffer}
  alias Membrane.{Opus, VP8, VP9}
  alias Membrane.WebM.Serializer

  def_input_pad :input,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers,
    # [Opus, VP8, VP9]
    caps: :any

  def_output_pad :output,
    availability: :always,
    mode: :pull,
    caps: :any

  @timestamp_scale 1_000_000

  @ebml_header {
    :EBML,
    [
      DocTypeReadVersion: 2,
      DocTypeVersion: 4,
      DocType: "webm",
      EBMLMaxSizeLength: 8,
      EBMLMaxIDLength: 4,
      EBMLReadVersion: 1,
      EBMLVersion: 1
    ]
  }

  @mock_info {
    :Info,
    [
      # TODO: calculate Duration dynamically
      Duration: 27201.0,
      WritingApp: "membrane_webm_plugin-0.1.0",
      MuxingApp: "membrane_webm_plugin-0.1.0",
      # FIXME: how should this field be populated
      Title: "Membrane WebM file",
      # hardcoded per RFC
      # note that this requires all incoming buffer `pts` timestamp to be expressed in Membrane.Time (i.e. in nanoseconds)
      # https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#name-timestampscale-element
      # FIXME: FIXME: FIXME:
      # Matroska's `TimecodeScale` changed it's name to `TimestampScale`
      # See https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#section-13
      # Yet the WebM documentation appears to still be using `TimecodeScale`
      # See https://www.webmproject.org/docs/container/#TimecodeScale
      TimestampScale: @timestamp_scale
    ]
  }

  # also known as MetaSeek
  # TODO: generate dynamically. quite challenging
  # note that the SeekPosition represents the byte offset from the beginning of the Segment of the top-level element with ID == SeekID
  # to recover the element_name:
  #   Membrane.WebM.Schema.element_id_to_name(Base.encode16(seek_id))
  @mock_seek {
    :SeekHead,
    [
      Seek: [SeekPosition: 431_238, SeekID: <<28, 83, 187, 107>>],
      Seek: [SeekPosition: 337, SeekID: <<18, 84, 195, 103>>],
      Seek: [SeekPosition: 3335, SeekID: <<22, 84, 174, 107>>],
      Seek: [SeekPosition: 161, SeekID: <<21, 73, 169, 102>>]
    ]
  }

  # Tracks: %{
  #         data: [
  #           TrackEntry: %{
  #             data: [
  #               CodecPrivate: %{
  #                 data: <<79, 112, 117, 115, 72, 101, 97, 100, 1, 6, 56, 1, 128,
  #                   187, 0, 0, 0, 0, 1, 4, 2, 0, 4, 1, 2, 3, 5>>,
  #                 data_size: 27
  #               },
  #               Audio: %{
  #                 data: [
  #                   BitDepth: %{data: 32, data_size: 1},
  #                   SamplingFrequency: %{data: 4.8e4, data_size: 8},
  #                   Channels: %{data: 6, data_size: 1}
  #                 ],
  #                 data_size: 17
  #               },
  #               TrackType: %{data: :audio, data_size: 1},
  #               SeekPreRoll: %{data: 80000000, data_size: 4},
  #               CodecDelay: %{data: 6500000, data_size: 3},
  #               CodecID: %{data: :opus, data_size: 6},
  #               Language: %{data: "und", data_size: 3},
  #               FlagLacing: %{data: 0, data_size: 1},
  #               TrackUID: %{data: 17399989374423545915, data_size: 8},
  #               TrackNumber: %{data: 2, data_size: 1}
  #             ],
  #             data_size: 97
  #           },
  #           TrackEntry: %{
  #             data: [
  #               Video: %{
  #                 data: [
  #                   Colour: %{
  #                     data: [
  #                       ChromaSitingVert: %{data: :half, data_size: 1},
  #                       ChromaSitingHorz: %{data: :left_collocated, data_size: 1}
  #                     ],
  #                     data_size: 8
  #                   },
  #                   FlagInterlaced: %{data: :progressive, data_size: 1},
  #                   PixelHeight: %{data: 1080, data_size: 2},
  #                   PixelWidth: %{data: 1920, data_size: 2}
  #                 ],
  #                 data_size: 22
  #               },
  #               DefaultDuration: %{data: 16666666, data_size: 3},
  #               TrackType: %{data: :video, data_size: 1},
  #               CodecID: %{data: :vp9, data_size: 5},
  #               Language: %{data: "und", data_size: 3},
  #               FlagLacing: %{data: 0, data_size: 1},
  #               TrackUID: %{data: 13024037295712538108, data_size: 8},
  #               TrackNumber: %{data: 1, data_size: 1}
  #             ],
  #             data_size: 72
  #           }
  #         ],
  #         data_size: 187
  #       },

  # TODO: There's no way of extracting this metadata from raw streams so a callback or option should be implemented to supply these values
  # Though they do not appear essential (possible exception: VLC)
  defp construct_tags() do
    {:Tags,
     [
       Tag: [
         SimpleTag: [TagString: "00:00:27.201000000", TagName: "DURATION"],
         SimpleTag: [TagString: "Lavc58.134.100 libopus", TagName: "ENCODER"],
         Targets: [TagTrackUID: 6_979_663_406_594_824_908]
       ],
       Tag: [
         SimpleTag: [TagString: "Lavf58.76.100", TagName: "ENCODER"],
         SimpleTag: [TagString: "Kevin MacLeod", TagName: "ARTIST"],
         SimpleTag: [TagString: "YouTube Audio Library", TagName: "ALBUM"],
         SimpleTag: [TagString: "Cinematic", TagName: "GENRE"],
         Targets: []
       ]
     ]}
  end

  defp construct_track_entry(%Opus{channels: channels} = _caps) do
    track_number = 1

    {:TrackEntry,
     [
       # CodecPrivate is identical to the ogg ID header specified here:
       # https://datatracker.ietf.org/doc/html/rfc7845#section-5.1
       # it can be ignored for opus streams with 1 or 2 channels but must be used to correctly play higher-channel-count streams
       CodecPrivate: construct_opus_id_header(channels),
       Audio: [
         # I guess this is hardcoded. Hard to tell from RFC
         BitDepth: 32,
         # Possible frequencies: 8, 12, 16, 24, 48 kHz
         # https://datatracker.ietf.org/doc/html/rfc6716#section-2
         SamplingFrequency: 2.4e4,
         Channels: channels
       ],
       # Tracktype: 2 for `audio`
       # https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#name-tracktype-values
       TrackType: 2,
       # FIXME: I don't understand SeekPreRoll: copying over from ffmpeg webm for now
       # https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#name-seekpreroll-element
       # https://opus-codec.org/docs/opusfile_api-0.5/group__stream__seeking.html
       SeekPreRoll: 80_000_000,
       # FIXME: How do I determine CodecDelay? copying over from ffmpeg webm for now
       # https://github.com/GStreamer/gstreamer/blob/5e3bf0fff7205390de56747f950f726b456fc65d/subprojects/gst-plugins-good/gst/matroska/matroska-mux.c#L1898
       # https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#section-8.1.4.1.28-1.14
       # https://datatracker.ietf.org/doc/html/rfc6716#section-2
       # The LP layer is based on the SILK codec [SILK].  It supports NB, MB,
       # or WB audio and frame sizes from 10 ms to 60 ms, and requires an
       # additional 5 ms look-ahead for noise shaping estimation.  A small
       # additional delay (up to 1.5 ms) may be required for sampling rate
       # conversion.
       # gstreamer has codecdelay set to 0
       CodecDelay: 3_250_000,
       CodecID: "A_OPUS",
       CodecName: "Opus Audio Codec",
       # I didn't find information about lacing in the Opus RFC so I assume it's always unlaced
       # https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#section-8.1.4.1.12
       FlagLacing: 0,
       #  TrackUID is an 8 byte number that MUST NOT be 0
       #  FIXME: :rand.uniform((1 <<< 56) - 2) works for now but :rand.uniform((1 <<< 64) - 2) should be used instead
       # Probably a problem with Membrane.WebM.EBML encoding of 8-byte numbers
       TrackUID: 6_979_663_406_594_824_908,
       # The track number as used in the Block Header (using more than 127 tracks is not encouraged, though the design allows an unlimited number).
       TrackNumber: track_number
     ]}
  end

  defp construct_track_entry(%VP8{width: width, height: height}) do
    track_number = 1

    {:TrackEntry,
     [
       Video: [
         Colour: [
           # :half,
           ChromaSitingVert: 2,
           # :left_coallocated
           ChromaSitingHorz: 1
         ],
         # :progressive, - no interlacing
         FlagInterlaced: 2,
         PixelHeight: width,
         PixelWidth: height
       ],
       DefaultDuration: 16_666_666,
       # :video,
       TrackType: 1,
       # :vp8,
       CodecID: "V_VP8",
       Language: "und",
       FlagLacing: 0,
       TrackUID: 13_024_037_295_712_538_108,
       TrackNumber: track_number
     ]}
  end

  defp construct_track_entry(%VP9{width: width, height: height}) do
    track_number = 1

    {:TrackEntry,
     [
       Video: [
         Colour: [
           # :half,
           ChromaSitingVert: 2,
           # :left_coallocated
           ChromaSitingHorz: 1
         ],
         # :progressive, - no interlacing
         FlagInterlaced: 2,
         PixelHeight: width,
         PixelWidth: height
       ],
       DefaultDuration: 16_666_666,
       # :video,
       TrackType: 1,
       # :vp8,
       CodecID: "V_VP9",
       Language: "und",
       FlagLacing: 0,
       TrackUID: 13_024_037_295_712_538_108,
       TrackNumber: track_number
     ]}
  end

  # ID header of the Ogg Encapsulation for the Opus Audio Codec
  # Used to populate the TrackEntry.CodecPrivate field
  # Required for correct playback of Opus tracks with more than 2 channels
  # https://datatracker.ietf.org/doc/html/rfc7845#section-5.1
  defp construct_opus_id_header(channels) do
    if channels > 2 do
      raise "Handling Opus channel counts of #{channels} is not supported. Cannot mux into a playable form."
    end

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

  defmodule State do
    defstruct cache: [],
              caps: nil,
              current_cluster_timecode: 0,
              current_block_timecode: nil,
              first_frame: true,
              caps_type: nil
  end

  @impl true
  def handle_caps(:input, %Opus{} = caps, _context, state) do
    {:ok, %State{state | caps: caps, caps_type: :opus}}
  end

  @impl true
  def handle_caps(:input, %VP8{width: _width, height: _height} = caps, _context, state) do
    {:ok, %State{state | caps: caps, caps_type: :vp8}}
  end

  @impl true
  def handle_caps(:input, %VP9{width: _width, height: _height} = caps, _context, state) do
    {:ok, %State{state | caps: caps, caps_type: :vp9}}
  end

  @impl true
  def handle_init(_) do
    # ebml_header = Serializer.serialize(@ebml_header)
    # {{:ok, buffer: {:output, %Buffer{payload: ebml_header}}}, %State{}}
    {:ok, %State{}}
  end

  @impl true
  def handle_demand(:output, _size, :buffers, _context, state) do
    {{:ok, demand: :input}, state}
  end

  # @impl true
  # def handle_demand(:input, _size, :buffers, _context, state) do
  #   {{:ok, demand: :input}, state}
  # end

  # @impl true
  # def handle_process(:input, %Buffer{payload: file}, _context, state) do
  #   header = Serializer.serialize({:EBML, file[:EBML]})
  #   segment = Serializer.serialize({:Segment, file[:Segment]})

  #   output = %Buffer{payload: header <> segment}
  #   {{:ok, buffer: {:output, output}}, state}
  # end

  @impl true
  def handle_process(:input, %Buffer{payload: data, pts: timestamp}, _context, state) do
    {{:ok, redemand: :output},
     %State{
       state
       | cache: [{div(timestamp, @timestamp_scale), data, 1, state.caps_type} | state.cache]
     }}
  end

  @impl true
  def handle_end_of_stream(:input, _context, state) do
    seek = @mock_seek
    info = @mock_info
    track_entry = construct_track_entry(state.caps)
    tracks = {:Tracks, [track_entry]}
    tags = construct_tags()
    cluster = construct_cluster(state.cache)

    ebml_header = Serializer.serialize(@ebml_header)
    segment = Serializer.serialize({:Segment, Enum.reverse([seek, info, tracks, tags, cluster])})

    webm_bytes = ebml_header <> segment

    {{:ok, buffer: {:output, %Buffer{payload: webm_bytes}}}, %State{first_frame: false}}
  end

  def construct_cluster(cache) do
    # TODO: pass additional data (timestamp, tracknumber) by appending it to `frame`

    subelements = Enum.map(cache, fn data -> {:SimpleBlock, data} end)
    subelements = [{:Timecode, 0} | subelements]

    {:Cluster, subelements}
  end
end

# Enum.map(cache, fn data -> {:SimpleBlock, data} end)
# cache= [  {27181000000,   <<220, 126, 0, 208, 138, 165, 188, 102, 38, 85, 165, 67, 55, 94, 141,     253, 211, 204, 166, 83, 145, 29, 199, 117, 46, 84, 185, 158, 255, 220,     94, 160, 72, 229, 43, 47, 164, 40, 67, 103, 0, 0, 132, 80>>},  {27161000000,   <<220, 77, 48, 9, 171, 53, 229, 45, 43, 22, 71, 117, 195, 250, 14, 115,     206, 98, 202, 68, 121, 165, 214, 155, 82, 73, 118, 11, 159, 221, 162,     52, 88, 163, 129, 73, 67, 117, 6, 96, 33, 246, 251>>},  {27141000000,   <<220, 76, 203, 169, 95, 75, 32, 71, 93, 4, 41, 50, 129, 51, 74, 70, 17,     114, 117, 152, 163, 43, 79, 254, 140, 146, 182, 57, 37, 247, 115, 8,     91, 112, 243, 97, 16, 155, 123, 117, 105, 168>>},  {27121000000,   <<220, 219, 193, 214, 13, 125, 199, 152, 175, 225, 203, 68, 9, 113, 3,     175, 12, 140, 70, 212, 41, 197, 157, 105, 56, 154, 117, 204, 223, 153,     239, 31, 161, 28, 120, 17, 87, 173, 39, 122, 215>>},  {27101000000,   <<220, 134, 46, 14, 201, 240, 207, 14, 137, 96, 43, 175, 168, 167, 158,     120, 42, 107, 33, 70, 52, 192, 157, 250, 154, 237, 115, 72, 159, 35,     70, 60, 84, 222, 75, 97, 245, 53, 235, 228>>},  {27081000000,   <<220, 124, 175, 213, 100, 148, 21, 25, 44, 169, 183, 24, 167, 150, 80,     140, 189, 23, 161, 57, 11, 145, 129, 144, 64, 26, 241, 229, 121, 16,     139, 31, 241, 165, 95, 83, 210, 101, 148>>},  {27061000000,   <<220, 128, 25, 79, 43, 213, 85, 203, 47, 124, 39, 252, 106, 58, 31, 212,     86, 43, 226, 72, 54, 142, 182, 160, 131, 254, 106, 182, 119, 246, 241,     100, 82, 19, 229, 55, 236, 54>>},  {27041000000,   <<220, 138, 62, 67, 225, 84, 103, 73, 253, 179, 7, 50, 199, 46, 198, 26,     154, 83, 86, 169, 128, 201, 64, 129, 125, 29, 220, 79, 223, 12, 223,     112, 85, 64, 75, 7, 198>>}]

"""
Opus:
  keyframe: always true - no mention in RFC
  lacing: always 00 - no mention in RFC
  invisible: always false - assumed
  discardable: always false - assumed

"""
