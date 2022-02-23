defmodule Membrane.WebM.Muxer do
  @moduledoc """
  Filter element for muxing WebM files.

  Muxer guidelines
  https://www.webmproject.org/docs/container/
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
    @moduledoc false
    defstruct tracks: %{},
              segment_size: 0,
              expected_tracks: 0,
              active_tracks: 0,
              accepting_pads: true,
              # cluster_acc holds: `serialized_list_of_blocks`, `cluster_timestamp`, `cluster_length_in_bytes`
              cluster_acc: {Serializer.serialize({:Timecode, 0}), :infinity, 0},
              cues: []
  end

  @impl true
  def handle_init(_options) do
    {:ok, %State{}}
  end

  @impl true
  def handle_prepared_to_playing(_context, state) do
    {:ok, %State{state | accepting_pads: false}}
  end

  @impl true
  def handle_pad_added(_pad, _context, state) do
    if state.accepting_pads do
      {:ok, %State{state | expected_tracks: state.expected_tracks + 1}}
    else
      raise "Can only add new input pads to muxer in state :prepared!"
    end
  end

  @impl true
  def handle_caps(Pad.ref(:input, id), caps, _context, state) do
    codec =
      case caps do
        %VP8{} -> :vp8
        %VP9{} -> :vp9
        %Opus{} -> :opus
        _other -> raise "unsupported codec #{inspect(caps)}"
      end

    state = update_in(state.active_tracks, fn t -> t + 1 end)
    type = Codecs.type(codec)

    track = %{
      track_number: state.active_tracks,
      id: id,
      codec: codec,
      caps: caps,
      type: type,
      last_timestamp: nil,
      last_block: nil
    }

    state = put_in(state.tracks[id], track)

    if state.active_tracks == state.expected_tracks do
      {segment_bytes, webm_header} = serialize_webm_header(state)
      new_state = %State{state | segment_size: state.segment_size + segment_bytes}

      {{:ok, [buffer: {:output, %Buffer{payload: webm_header}}, demand: Pad.ref(:input, id)]},
       new_state}
    else
      {{:ok, demand: Pad.ref(:input, id)}, state}
    end
  end

  defp serialize_webm_header(state) do
    ebml_header = Serializer.serialize(Elements.construct_ebml_header())

    segment_header = Serializer.serialize_segment_header()

    info = Elements.construct_info()
    tracks = Elements.construct_tracks(state.tracks)
    # tags = Elements.construct_tags()
    seek_head = Elements.construct_seek_head([info, tracks])
    void = Elements.construct_void(seek_head)

    webm_header_elements = Serializer.serialize([seek_head, void, info, tracks])

    segment_size = byte_size(webm_header_elements)

    {segment_size, ebml_header <> segment_header <> webm_header_elements}
  end

  # demand all tracks for which the last frame is not cached
  @impl true
  def handle_demand(:output, _size, :buffers, _context, state) do
    if state.expected_tracks == state.active_tracks do
      demands =
        state.tracks
        |> Enum.filter(fn {_id, info} -> info.last_block == nil end)
        |> Enum.map(fn {id, _info} -> {:demand, Pad.ref(:input, id)} end)

      {{:ok, demands}, state}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_process(Pad.ref(:input, id), %Buffer{payload: data} = buffer, _context, state) do
    timestamp = Buffer.get_dts_or_pts(buffer) |> div(@timestamp_scale)
    state = put_in(state.tracks[id].last_timestamp, timestamp)
    block = {timestamp, data, state.tracks[id].track_number, state.tracks[id].codec}
    state = put_in(state.tracks[id].last_block, block)

    if Enum.any?(state.tracks, fn {_id, info} -> info.last_block == nil end) do
      # if there are active tracks without a cached frame then demand it
      {{:ok, redemand: :output}, state}
    else
      consume_block(state)
    end
  end

  # the cache contains one frame for each track
  # takes the frame that should come next and appends it to current cluster or creates a new cluster and outputs current cluster
  defp consume_block(state) do
    # sort blocks according to which should be next in the cluster
    youngest_track =
      state.tracks
      |> Enum.sort(&block_sorter/2)
      |> hd()
      |> elem(1)

    block = youngest_track.last_block

    {returned_cluster, new_cluster_acc} = step_cluster(block, state.cluster_acc)

    state = put_in(state.tracks[youngest_track.id].last_block, nil)

    if returned_cluster == nil do
      {{:ok, redemand: :output}, %State{state | cluster_acc: new_cluster_acc}}
    else
      # CueTime - absolute timestamp
      # CueTrack - track number
      # CueClusterPosition - SegmentPosition of the Cluster containing the associated Block

      # Unless Matroska is used as a live stream, it SHOULD contain a Cues Element.
      # For each video track, each keyframe SHOULD be referenced by a CuePoint Element.
      # It is RECOMMENDED to not reference non-keyframes of video tracks in Cues unless it references a Cluster Element which contains a CodecState Element but no keyframes.
      # For each subtitle track present, each subtitle frame SHOULD be referenced by a CuePoint Element with a CueDuration Element.
      # References to audio tracks MAY be skipped in CuePoint Elements if a video track is present. When included the CuePoint Elements SHOULD reference audio keyframes at most once every 500 milliseconds.
      # If the referenced frame is not stored within the first SimpleBlock, or first BlockGroup within its Cluster Element, then the CueRelativePosition Element SHOULD be written to reference where in the Cluster the reference frame is stored.
      # If a CuePoint Element references Cluster Element that includes a CodecState Element, then that CuePoint Element MUST use a CueCodecState Element.
      # CuePoint Elements SHOULD be numerically sorted in storage order by the value of the CueTime Element.
      # https://www.matroska.org/technical/cues.html
      new_cue =
        {:CuePoint,
         [
           CueTime: elem(block, 0),
           CueTrack: youngest_track.track_number,
           CueClusterPosition: state.segment_size
         ]}

      state = update_in(state.cues, fn cues -> [new_cue | cues] end)
      cluster_bytes = Serializer.serialize({:Cluster, returned_cluster})
      new_segment_size = state.segment_size + byte_size(cluster_bytes)

      {{:ok, buffer: {:output, %Buffer{payload: cluster_bytes}}, redemand: :output},
       %State{state | cluster_acc: new_cluster_acc, segment_size: new_segment_size}}
    end
  end

  # Group Blocks into Clusters.

  # A Matroska file SHOULD contain at least one Cluster Element.
  # Cluster Elements contain frames of every track sorted by timestamp in monotonically increasing order.
  # It is RECOMMENDED that the size of each individual Cluster Element be limited to store no more than 5 seconds or 5 megabytes (but 32.767 seconds is possible).

  # Every Cluster Element MUST contain a Timestamp Element - occuring once per cluster placed at the very beginning.
  # All Block timestamps inside the Cluster are relative to that Cluster's Timestamp:
  # Absolute Timestamp = Block+Cluster
  # Relative Timestamp = Block
  # Raw Timestamp = (Block+Cluster)*TimestampScale
  # Matroska RFC https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#section-7-18

  # Clusters MUST begin with a keyframe.
  # Audio blocks that contain the video key frame's timecode MUST be in the same cluster as the video key frame block.
  # Audio blocks that have the same absolute timecode as video blocks SHOULD be written before the video blocks.
  # This implementation simply splits the stream on every video keyframe if a video track is present. Otherwise the 5mb/5s limits are used.

  # WebM Muxer Guidelines https://www.webmproject.org/docs/container/
  defp step_cluster(
         {absolute_time, data, track_number, type} = block,
         {current_cluster, cluster_time, current_bytes} = _cluster_acc
       ) do
    cluster_time = min(cluster_time, absolute_time)
    relative_time = absolute_time - cluster_time

    # 32767 is max valid value of a simpleblock timecode (max signed_int16)
    if relative_time * @timestamp_scale > Membrane.Time.milliseconds(32_767) do
      IO.warn("Simpleblock timecode overflow. Still writing but some data will be lost.")
    end

    begin_new_cluster =
      current_bytes >= @cluster_bytes_limit or
        relative_time * @timestamp_scale >= @cluster_time_limit or
        Codecs.is_video_keyframe(block)

    if begin_new_cluster do
      timecode = {:Timecode, absolute_time}
      new_block = {:SimpleBlock, {0, data, track_number, type}}
      new_cluster = Serializer.serialize([timecode, new_block])
      bytes = byte_size(new_cluster)
      new_cluster_acc = {new_cluster, absolute_time, bytes}

      if current_cluster == <<>> do
        {nil, new_cluster_acc}
      else
        {current_cluster, new_cluster_acc}
      end
    else
      new_block = {:SimpleBlock, {absolute_time - cluster_time, data, track_number, type}}
      serialized_block = Serializer.serialize(new_block)
      new_cluster = current_cluster <> serialized_block
      new_bytes = current_bytes + byte_size(serialized_block)
      new_cluster_acc = {new_cluster, cluster_time, new_bytes}

      {nil, new_cluster_acc}
    end
  end

  defp block_sorter({_id1, track1}, {_id2, track2}) do
    {time1, _data1, _track_number1, codec1} = track1.last_block
    {time2, _data2, _track_number2, codec2} = track2.last_block

    if time1 < time2 do
      true
    else
      Codecs.type(codec1) == :audio and Codecs.type(codec2) == :video
    end
  end

  @impl true
  def handle_end_of_stream(Pad.ref(:input, id), _context, state) do
    new_block = state.tracks[id].last_block
    {blocks, timecode, bytes} = state.cluster_acc
    # TODO: this should be handled by step_cluster; now bytes is incorrect
    put_in(state.cluster_acc, {[new_block | blocks], timecode, bytes})

    if state.active_tracks == 1 do
      {blocks, _timecode, _bytes} = state.cluster_acc
      cluster_bytes = Serializer.serialize({:Cluster, blocks})
      new_segment_size = state.segment_size + byte_size(cluster_bytes)
      state = %State{state | segment_size: new_segment_size}
      cues_bytes = Serializer.serialize({:Cues, state.cues})

      {{:ok,
        buffer: {:output, %Buffer{payload: cluster_bytes <> cues_bytes}}, end_of_stream: :output},
       state}
    else
      {_track, state} = pop_in(state.tracks[id])
      {actions, state} = consume_block(state)

      {actions,
       %State{
         state
         | active_tracks: state.active_tracks - 1,
           expected_tracks: state.expected_tracks - 1
       }}
    end
  end
end
