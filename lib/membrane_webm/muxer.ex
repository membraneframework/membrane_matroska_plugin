defmodule Membrane.WebM.Muxer do
  @moduledoc """
  Module for muxing WebM files.


  Muxer guidelines
  https://www.webmproject.org/docs/container/

  Muxers should treat all guidelines marked SHOULD in this section as MUST.
  This will foster consistency across WebM files in the real world.

  - WebM SHOULD contain the SeekHead element.
      - Reason: Allows the client to know if the file contains a Cues element.
  - WebM files SHOULD include a keyframe-only Cues element.
      - The Cues element SHOULD contain only video key frames, to decrease the size of the file header.
      - It is recommended that the Cues element be before any clusters, so that the client can seek to a point
        in the data that has not yet been downloaded in a single seek operation. Ref: a tool that will put the Cues at the front.
  - All absolute (block + cluster) timecodes MUST be monotonically increasing.
      - All timecodes are associated with the start time of the block.
  - The TimecodeScale element SHOULD be set to a default of 1.000.000 nanoseconds.
      - Reason: Allows every cluster to have blocks with positive values up to 32.767 seconds.
  - Key frames SHOULD be placed at the beginning of clusters.
      - Having key frames at the beginning of clusters should make seeking faster and easier for the client.
  - Audio blocks that contain the video key frame's timecode SHOULD be in the same cluster as the video key frame block.
  - Audio blocks that have same absolute timecode as video blocks SHOULD be written before the video blocks.
  - WebM files MUST only support pixels for the DisplayUnit element.
  """
  use Bitwise
  use Bunch

  use Membrane.Filter

  alias Membrane.{Buffer}
  alias Membrane.{Opus, VP8, VP9}
  alias Membrane.WebM.Serializer
  alias Membrane.WebM.Plugin.Mixfile

  def_input_pad :input,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers,
    caps: [Opus, VP8, VP9]

  def_output_pad :output,
    availability: :always,
    mode: :pull,
    caps: :any

  # 5 mb
  @cluster_bytes_limit 5_242_880
  @cluster_time_limit Membrane.Time.seconds(5)
  @timestamp_scale Membrane.Time.millisecond()
  @version Mixfile.project()[:version]
  @bytes_reserved_for_seekhead 160

  @seekable_elements [
    :Info,
    :Tracks,
    :Tags
    # :Cues, # TODO: implement; insert before first :Cluster
  ]

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

  # this element MUST exist - because of TimestampScale
  @mock_info {
    :Info,
    [
      # TODO: calculate Duration dynamically
      Duration: 27201.0,
      WritingApp: "membrane_webm_plugin-#{@version}",
      MuxingApp: "membrane_webm_plugin-#{@version}",
      # FIXME: how should the title field be populated?
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

  # TODO: There's no way of extracting this metadata from raw streams so a callback or option should be implemented to supply these values
  # Though they do not appear essential for achieving playable files (possible exception: VLC)
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
           # TODO: how do I know how to set these fields?
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
       # TODO: where did this come from?
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

    # option descriptions copied over from ogg_plugin:
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
    {:ok, %State{}}
  end

  @impl true
  def handle_demand(:output, _size, :buffers, _context, state) do
    {{:ok, demand: :input}, state}
  end

  # TODO: for now accumulates everything in cache and serializes at end of the input stream which is suboptimal
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
    info = @mock_info
    track_entry = construct_track_entry(state.caps)
    tracks = {:Tracks, [track_entry]}
    tags = construct_tags()
    clusters = construct_clusters(state.cache, state.caps_type)

    seek_head = construct_seek_head([info, tracks, tags])
    void_width = @bytes_reserved_for_seekhead - byte_size(Serializer.serialize(seek_head))
    void = {:Void, void_width}

    ebml_header = Serializer.serialize(@ebml_header)

    segment =
      Serializer.serialize(
        {:Segment, Enum.reverse([seek_head, void, info, tracks, tags] ++ clusters)}
      )

    webm_bytes = ebml_header <> segment

    {{:ok, buffer: {:output, %Buffer{payload: webm_bytes}}}, %State{first_frame: false}}
  end

  @doc """
  segment position:
  https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#name-segment-position
  """
  defp construct_seek_head(elements) do
    seeks =
      elements
      |> Enum.reduce({[], @bytes_reserved_for_seekhead + 1}, fn element, acc ->
        {name, data} = element
        {results, offset} = acc
        new_acc = [{name, offset} | results]
        new_offset = offset + byte_size(Serializer.serialize({name, data}))
        {new_acc, new_offset}
      end)
      |> elem(0)
      |> Enum.map(fn {name, offset} ->
        {:Seek,
         [
           {:SeekPosition, offset},
           {:SeekID, Base.decode16!(Membrane.WebM.Schema.name_to_element_id(name))}
         ]}
      end)

    {:SeekHead, seeks}
  end

  @doc """
  Pack accumulated frames into Blocks and group them into Clusters.

  A Matroska file SHOULD contain at least one Cluster Element.
  Cluster Elements contain frames of every track sorted by timestamp in monotonically increasing order.
  It is RECOMMENDED that the size of each individual Cluster Element be limited to store no more than 5 seconds or 5 megabytes (but 32.767 is possible).

  Every Cluster Element MUST contain a Timestamp Element - occuring once per cluster placed at the very beginning.
  All Block timestamps inside the Cluster are relative to that Cluster's Timestamp:
  Absolute Timestamp = Block+Cluster
  Relative Timestamp = Block
  Raw Timestamp = (Block+Cluster)*TimestampScale
  Matroska RFC https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#section-7-18

  Clusters MUST begin with a keyframe.
  Audio blocks that contain the video key frame's timecode MUST be in the same cluster as the video key frame block.
  Audio blocks that have the same absolute timecode as video blocks SHOULD be written before the video blocks.
  This implementation simply splits the stream on every video keyframe if a video track is present. Otherwise the 5mb/5s limits are used.

  WebM Muxer Guidelines https://www.webmproject.org/docs/container/
  """
  defp construct_clusters(cache, caps_type) do
    fragments = reduce_with_limits(cache)
    # Enum.reduce(fragments, {[]}, step_fragments_to_clusters)

    Enum.map(fragments, fn {blocks, timecode} -> {:Cluster, blocks ++ [{:Timecode, timecode}]} end)
    # clusters = Enum.reduce(blocks, {[], 0, 0, [], []}, &step_blocks_to_clusters()/2)
    # cluster_data = [{:Timecode, 0} | blocks]

    # {:Cluster, cluster_data}
  end

  # def step_blocks_to_clusters(fragment, acc) do
  #   {:SimpleBlock, {timecode, _data, _caps_type}} = fragment # FIXME:
  #   {result_clusters, cluster_time, cluster_bytes, valid_cluster_blocks, rest_processed_blocks} = acc
  #   case
  #   if
  # end

  def reduce_with_limits(blocks) do
    IO.puts("reduce")
    acc = %{
      chunks: [], # list of valid clusters to return
      current_chunk: {[], 999_999_999},
      current_bytes: 0,
      current_time: 0,
      previous_timecode: 0
    }
    # File.write!("dumpsko", inspect(blocks, limit: :infinity, pretty: true))
    %{
      chunks: chunks,
      current_chunk: current_chunk,
    } = Enum.reduce(Enum.reverse(blocks), acc, fn block, acc -> step_reduce(block, acc) end)
    Enum.reverse([current_chunk | chunks])
  end

  def step_reduce(
    {timecode, data, track_number, type} = block, %{
      chunks: chunks,
      current_chunk: {current_chunk, chunk_timecode},
      current_bytes: current_bytes,
      current_time: current_time,
      previous_timecode: previous_timecode,
    } = _acc) do

    block_bytes = byte_size(data) + 7 #TODO: maybe don't add 7?
    # this is only an approximation because VINTs are used
    # 2 + # timecode
    # 1 + # header_flags
    # 1 + # track_number - only correct as long as less than 128 tracks in file
    # 1 + # element_id
    # 2 + # element_size - should be correct in most cases (122 to 16378 byte frames)

    chunk_timecode = min(chunk_timecode, timecode)
    current_bytes = current_bytes + block_bytes
    current_time = current_time + Membrane.Time.milliseconds(timecode - previous_timecode)

    # IO.inspect(acc)

    if current_bytes >= @cluster_bytes_limit or current_time >= @cluster_time_limit or video_keyframe(block) and current_chunk != [] do
      block = {:SimpleBlock, {0, data, track_number, type}}
      %{
        chunks: [{current_chunk, chunk_timecode} | chunks],
        current_chunk: {[block], timecode},
        current_bytes: 0,
        current_time: 0,
        previous_timecode: timecode
      }
    else
      block = {:SimpleBlock, {timecode - chunk_timecode, data, track_number, type}}
      %{
        chunks: chunks,
        current_chunk: {[block | current_chunk], chunk_timecode},
        current_bytes: current_bytes,
        current_time: current_time,
        previous_timecode: timecode
      }
    end
  end

  # TODO: does not take audio into account
  def video_fragments(blocks) do
    # blocks |> Enum.filter(&keyframe/1) |> Enum.map(&elem(&1, 0)) |> IO.inspect()
    # if there is some video track:
      # split on video keyframes
    blocks |> Bunch.Enum.chunk_by_prev(fn _x, y -> not video_keyframe(y) end)
      # TODO: now if we have bad clusters: 5s/5mb print warnings but nothing can be done
      # if some cluster exceeds 32.67 seconds that's unplayable TODO: check inside simpleblock? less expensive to check here
      # I guess this can still be serialized and it should work for 30 seconds
    # else if there is only audio
      # reduce with 5s 5mb limit
  end

  def video_keyframe({_timecode, _data, _track_number, type} = block) do
    if type == :vp8 or type == :vp9 do
      keyframe(block)
    else
      false
    end
  end

  def keyframe({_timecode, data, _track_number, type} = _block) do
    case type do
      :opus -> true
      :vorbis -> true
      :vp8 -> Serializer.vp8_frame_type(data) == 0
      :vp9 -> Serializer.vp9_frame_type(data) == 0
      _ -> raise "unknown codec #{type}"
    end
  end

  # https://www.matroska.org/technical/cues.html
  defp construct_cues() do
    nil
  end
end
