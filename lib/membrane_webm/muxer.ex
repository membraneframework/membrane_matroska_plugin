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
    availability: :on_request,
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
              tracks: %{},
              expected_tracks: 0,
              active_tracks: 0,
              current_cluster_timecode: 0,
              current_block_timecode: nil,
              contains_video: false,
              cluster: %{
                current_cluster: {[], 999_999_999},
                current_bytes: 0,
                current_time: 0,
                previous_time: 0
              }
  end

  @impl true
  def handle_pad_added(_pad, _context, state) do
    {:ok, %State{state | expected_tracks: state.expected_tracks + 1}}
  end

  @impl true
  def handle_caps(Pad.ref(:input, id), caps, _context, state) do
    # FIXME: id is a source of nondeterminism - makes testing difficult
    # also it shouldn't be assigned via input pad but generated in muxer
    # imho best: leave option to provide input pad but generate random id if none provided
    state = update_in(state.active_tracks, fn t -> t + 1 end)
    is_video = Codecs.is_video(caps)

    track = %{
      track_number: state.active_tracks,
      id: id,
      caps: caps,
      is_video: is_video,
      last_timestamp: nil
    }

    state = put_in(state.tracks[id], track)
    state = if is_video, do: put_in(state.contains_video, true), else: state

    if state.active_tracks == state.expected_tracks do
      {{:ok,
        demand: Pad.ref(:input, id),
        buffer: {:output, %Buffer{payload: serialize_webm_header(state)}}}, state}
      # FIXME: i can calculate duration only at the end of the stream so the whole webm_header and it's length should be saved; recalculated at the end of the stream and the file stitched together along with seek and cues
    else
      {{:ok, demand: Pad.ref(:input, id)}, state}
    end
  end

  def serialize_webm_header(state) do
    info = Elements.construct_info()
    tracks = Elements.construct_tracks(state.tracks)
    tags = Elements.construct_tags()
    seek_head = Elements.construct_seek_head([info, tracks, tags])
    void = Elements.construct_void(seek_head)

    ebml_header = Serializer.serialize(Elements.construct_ebml_header())

    segment_beginning =
      Serializer.serialize({:Segment, Enum.reverse([seek_head, void, info, tracks, tags])})

    ebml_header <> segment_beginning
  end

  @impl true
  def handle_init(_) do
    {:ok, %State{}}
  end

  @impl true
  def handle_demand(:output, _size, :buffers, _context, state) do
    {{:ok, Enum.map(state.tracks, fn {id, _info} -> {:demand, Pad.ref(:input, id)} end)}, state}
  end

  # TODO: for now accumulates everything in cache and serializes at end of input stream which is suboptimal
  # TODO: ivf sends pts while muxer needs dts
  @impl true
  def handle_process(Pad.ref(:input, id), %Buffer{payload: data, pts: timestamp}, _context, state) do
    {{:ok, redemand: :output},
     %State{
       state
       | cache: [
           {div(timestamp, @timestamp_scale), data, state.tracks[id].track_number, id}
           | state.cache
         ]
     }}
  end

  @impl true
  def handle_end_of_stream(Pad.ref(:input, _id), _context, state) do
    if state.active_tracks == 1 do
      blocks = Enum.sort(state.cache, &block_sorter/2)
      clusters = blocks |> construct_clusters()
      Enum.map(clusters, fn cluster -> IO.inspect(elem(cluster, 1)[:Timecode]) end)
      clusters_bytes = clusters |> Serializer.serialize()

      {{:ok, buffer: {:output, %Buffer{payload: clusters_bytes}}, end_of_stream: :output}, state}
    else
      {:ok, %State{state | active_tracks: state.active_tracks - 1}}
    end
  end

  defp block_sorter({time1, _data1, _track1, codec1}, {time2, _data2, _track2, codec2}) do
    if time1 < time2 do
      true
    else
      Codecs.is_audio(codec1) and Codecs.is_video(codec2)
    end
  end

  @doc """
  Pack accumulated frames into Blocks and group them into Clusters.

  A Matroska file SHOULD contain at least one Cluster Element.
  Cluster Elements contain frames of every track sorted by timestamp in monotonically increasing order.
  It is RECOMMENDED that the size of each individual Cluster Element be limited to store no more than 5 seconds or 5 megabytes (but 32.767 seconds is possible).

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
      previous_time: 0
    }

    %{
      clusters: clusters,
      current_cluster: current_cluster
    } =
      Enum.reduce(blocks, acc, fn block, acc ->
        step_reduce_with_limits(block, acc)
      end)

    [current_cluster | clusters]
    |> Enum.reverse()
    |> Enum.map(fn {blocks, timecode} -> {:Cluster, blocks ++ [{:Timecode, timecode}]} end)
  end

  def step_reduce_with_limits(
        {absolute_time, data, track_number, type} = block,
        %{
          clusters: clusters,
          current_cluster: {current_cluster, cluster_time},
          current_bytes: current_bytes,
          current_time: current_time,
          previous_time: previous_time
        } = _acc
      ) do
    # TODO: maybe don't add 7? doesn't make much difference
    # 7 is only an approximation because VINTs (variable-length ints) are used
    # +2 # timecode
    # +1 # header_flags
    # +1 # track_number - only correct as long as less than 128 tracks in file
    # +1 # element_id
    # +2 # element_size - should be correct in most cases (122 to 16378 byte frames)

    cluster_time = min(cluster_time, absolute_time)
    current_bytes = current_bytes + byte_size(data) + 7
    current_time = current_time + Membrane.Time.milliseconds(absolute_time - previous_time)

    # 32767 is max valid value of a simpleblock timecode (max signed_int16)
    if current_time > Membrane.Time.milliseconds(32767) do
      IO.warn("Simpleblock timecode overflow. Still writing but some data will be lost.")
    end

    if current_bytes >= @cluster_bytes_limit or current_time >= @cluster_time_limit or
         Codecs.is_video_keyframe(block) do
      block = {:SimpleBlock, {0, data, track_number, type}}

      %{
        clusters: [{current_cluster, cluster_time} | clusters],
        current_cluster: {[block], absolute_time},
        current_bytes: 0,
        current_time: 0,
        previous_time: absolute_time
      }
    else
      block = {:SimpleBlock, {absolute_time - cluster_time, data, track_number, type}}

      %{
        clusters: clusters,
        current_cluster: {[block | current_cluster], cluster_time},
        current_bytes: current_bytes,
        current_time: current_time,
        previous_time: absolute_time
      }
    end
  end
end
