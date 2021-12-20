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
  alias Membrane.WebM.Parser.Codecs

  alias Membrane.WebM.Serializer.Elements

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
  # TODO: ivf sends pts while muxer needs dts
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
    info = Elements.construct_info()
    tracks = Elements.construct_tracks(state.caps)
    tags = Elements.construct_tags()
    seek_head = Elements.construct_seek_head([info, tracks, tags])
    void = Elements.construct_void(seek_head)
    clusters = construct_clusters(state.cache)

    ebml_header = Serializer.serialize(Elements.construct_ebml_header())

    segment =
      Serializer.serialize(
        {:Segment, Enum.reverse([seek_head, void, info, tracks, tags] ++ clusters)}
      )

    webm_bytes = ebml_header <> segment

    {{:ok, buffer: {:output, %Buffer{payload: webm_bytes}}, end_of_stream: :output},
     %State{first_frame: false}}
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
  def construct_clusters(blocks) do
    acc = %{
      clusters: [],
      current_cluster: {[], 999_999_999},
      current_bytes: 0,
      current_time: 0,
      previous_timecode: 0
    }

    %{
      clusters: clusters,
      current_cluster: current_cluster
    } =
      Enum.reduce(Enum.reverse(blocks), acc, fn block, acc ->
        step_reduce_with_limits(block, acc)
      end)

    [current_cluster | clusters]
    |> Enum.reverse()
    |> Enum.map(fn {blocks, timecode} -> {:Cluster, blocks ++ [{:Timecode, timecode}]} end)
  end

  def step_reduce_with_limits(
        {timecode, data, track_number, type} = block,
        %{
          clusters: clusters,
          current_cluster: {current_cluster, cluster_timecode},
          current_bytes: current_bytes,
          current_time: current_time,
          previous_timecode: previous_timecode
        } = _acc
      ) do
    # TODO: maybe don't add 7?
    block_bytes = byte_size(data) + 7
    # this is only an approximation because VINTs are used
    # 2 + # timecode
    # 1 + # header_flags
    # 1 + # track_number - only correct as long as less than 128 tracks in file
    # 1 + # element_id
    # 2 + # element_size - should be correct in most cases (122 to 16378 byte frames)

    cluster_timecode = min(cluster_timecode, timecode)
    current_bytes = current_bytes + block_bytes
    current_time = current_time + Membrane.Time.milliseconds(timecode - previous_timecode)

    if current_bytes >= @cluster_bytes_limit or current_time >= @cluster_time_limit or
         (Codecs.video_keyframe(block) and current_cluster != []) do
      block = {:SimpleBlock, {0, data, track_number, type}}

      %{
        clusters: [{current_cluster, cluster_timecode} | clusters],
        current_cluster: {[block], timecode},
        current_bytes: 0,
        current_time: 0,
        previous_timecode: timecode
      }
    else
      block = {:SimpleBlock, {timecode - cluster_timecode, data, track_number, type}}

      %{
        clusters: clusters,
        current_cluster: {[block | current_cluster], cluster_timecode},
        current_bytes: current_bytes,
        current_time: current_time,
        previous_timecode: timecode
      }
    end
  end
end
