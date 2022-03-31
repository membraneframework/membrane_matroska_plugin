defmodule Membrane.WebM.Muxer do
  @moduledoc """
  Filter element for muxing WebM files.

  It accepts an arbitrary number of Opus, VP8 or VP9 streams and outputs a bytestream in WebM format containing those streams.

  Muxer guidelines
  https://www.webmproject.org/docs/container/
  """
  use Bitwise
  use Bunch

  use Membrane.Filter

  alias Membrane.{Buffer, RemoteStream}
  alias Membrane.{Opus, VP8, VP9}
  alias Membrane.WebM.Parser.Codecs
  alias Membrane.WebM.Serializer
  alias Membrane.WebM.Serializer.Helper

  def_input_pad :input,
    availability: :on_request,
    mode: :pull,
    demand_unit: :buffers,
    caps: [Opus, VP8, VP9]

  def_output_pad :output,
    availability: :always,
    mode: :pull,
    caps: {RemoteStream, content_format: :WEBM}

  # 5 mb
  @cluster_bytes_limit 5_242_880
  @cluster_time_limit Membrane.Time.seconds(5)
  @timestamp_scale Membrane.Time.millisecond()

  defmodule State do
    @moduledoc false
    defstruct tracks: %{},
              segment_position: 0,
              expected_tracks: 0,
              active_tracks: 0,
              cluster_acc: Helper.serialize({:Timecode, 0}),
              cluster_time: :infinity,
              cluster_size: 0,
              cues: []
  end

  @impl true
  def handle_init(_options) do
    {:ok, %State{}}
  end

  @impl true
  def handle_pad_added(_pad, context, state) when context.playback_state != :playing do
    {:ok, %State{state | expected_tracks: state.expected_tracks + 1}}
  end

  @impl true
  def handle_pad_added(_pad, _context, _state) do
    raise "Can't add new input pads to muxer in state :playing!"
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

    state = update_in(state.active_tracks, &(&1 + 1))
    type = Codecs.type(codec)

    track = %{
      track_number: state.active_tracks,
      id: id,
      codec: codec,
      caps: caps,
      type: type,
      last_timestamp: nil,
      last_block: nil,
    }

    state = put_in(state.tracks[id], track)

    if state.active_tracks == state.expected_tracks do
      {segment_position, webm_header} = Serializer.WebM.serialize_webm_header(state.tracks)
      new_state = %State{state | segment_position: state.segment_position + segment_position}
      demands = Enum.map(state.tracks, fn {id, _track_data} -> {:demand, Pad.ref(:input, id)} end)
      {{:ok, [{:buffer, {:output, %Buffer{payload: webm_header}}} | demands]}, new_state}
    else
      {:ok, state}
    end
  end

  # demand all tracks for which the last frame is not cached
  @impl true
  def handle_demand(:output, _size, :buffers, _context, state)
      when state.expected_tracks == state.active_tracks do
    demands =
      state.tracks
      |> Enum.filter(fn {_id, info} -> info.last_block == nil end)
      |> Enum.map(fn {id, _info} -> {:demand, Pad.ref(:input, id)} end)

    {{:ok, demands}, state}
  end

  @impl true
  def handle_demand(:output, _size, :buffers, _context, state) do
    {:ok, state}
  end

  @impl true
  def handle_process(pad_ref, buffer, _context, state) do
    state = ingest_buffer(state, pad_ref, buffer)

    # if there are active tracks without a cached block then demand it
    if Enum.any?(state.tracks, fn {_id, track} -> track.last_block == nil end) do
      {{:ok, redemand: :output}, state}
    else
      process_next_block_and_return(state)
    end
  end

  def ingest_buffer(state, Pad.ref(:input, id), %Buffer{payload: data} = buffer) do
    # update last timestamp
    timestamp = div(Buffer.get_dts_or_pts(buffer), @timestamp_scale)
    state = put_in(state.tracks[id].last_timestamp, timestamp)
    # cache last block
    block = {timestamp, data, state.tracks[id].track_number, state.tracks[id].codec}
    put_in(state.tracks[id].last_block, block)
  end

  # one block is cached for each track
  # takes the block that should come next and appends it to current cluster or creates a new cluster for it and outputs the current cluster
  defp process_next_block(state) do
    state
    |> pop_next_block()
    |> step_cluster()
  end

  def process_next_block_and_return(state) do
    {state, maybe_cluster} = process_next_block(state)

    case maybe_cluster do
      <<>> ->
        {{:ok, redemand: :output}, state}
      serialized_payload ->
        {{:ok, buffer: {:output, %Buffer{payload: serialized_payload}}, redemand: :output}, state}
    end
  end

  def pop_next_block(state) do
    # find next block
    {id, track} = hd(Enum.sort(state.tracks, &block_sorter/2))
    block = track.last_block
    # delete the block from state
    state = put_in(state.tracks[id].last_block, nil)

    {state, block}
  end

  # https://www.matroska.org/technical/cues.html
  def add_cluster_cuepoint(state, track_number) do
    new_cue = {:CuePoint,
        [
          # Absolute timestamp according to the Segment time base.
          CueTime: state.cluster_time,
          CueTrack: track_number,
          # The Segment Position of the Cluster containing the associated Block.
          CueClusterPosition: state.segment_position
        ]}

    update_in(state.cues, fn cues -> [new_cue | cues] end)
  end

  # Groups Blocks into Clusters.
  #   All Block timestamps inside the Cluster are relative to that Cluster's Timestamp:
  #   Absolute Timestamp = Block+Cluster
  #   Relative Timestamp = Block
  #   Raw Timestamp = (Block+Cluster)*TimestampScale
  # Matroska RFC https://www.ietf.org/archive/id/draft-ietf-cellar-matroska-08.html#section-7-18
  # WebM Muxer Guidelines https://www.webmproject.org/docs/container/
  defp step_cluster(
          {%State{cluster_acc: current_cluster_acc, cluster_time: cluster_time, cluster_size: cluster_size} = state,
         {absolute_time, data, track_number, type} = block}
       ) do
    cluster_time = min(cluster_time, absolute_time)
    relative_time = absolute_time - cluster_time

    # 32767 is max valid value of a simpleblock timecode (max signed_int16)
    if relative_time * @timestamp_scale > Membrane.Time.milliseconds(32_767) do
      IO.warn("Simpleblock timecode overflow. Still writing but some data will be lost.")
    end

    # FIXME: The new cluster should be created BEFORE this condition is met
    begin_new_cluster =
      cluster_size >= @cluster_bytes_limit or
        relative_time * @timestamp_scale >= @cluster_time_limit or
        Codecs.is_video_keyframe?(block)

    if begin_new_cluster do
      timecode = {:Timecode, absolute_time}
      simple_block = {:SimpleBlock, {0, data, track_number, type}}
      new_cluster = Helper.serialize([timecode, simple_block])
      state = add_cluster_cuepoint(%State{
        state |
        cluster_acc: new_cluster,
        cluster_time: absolute_time,
        cluster_size: byte_size(new_cluster),
      },
      track_number)

      if current_cluster_acc == <<>> do
        {state, <<>>}
      else
        serialized_cluster = Helper.serialize({:Cluster, current_cluster_acc})
        state = update_in(state.segment_position, & &1 + byte_size(serialized_cluster))

        # return serialized cluster
        {state, serialized_cluster}
      end
    else
      simple_block = {:SimpleBlock, {absolute_time - cluster_time, data, track_number, type}}
      serialized_block = Helper.serialize(simple_block)
      state = update_in(state.cluster_acc, & &1 <> serialized_block)
      state = update_in(state.cluster_size, & &1 + byte_size(serialized_block))

      {state, <<>>}
    end
  end

  # Blocks are written in timestamp order.
  # Per WebM Muxer Guidelines:
  # FIXME: this condition is not supported
  # - Audio blocks that contain the video key frame's timecode SHOULD be in the same cluster
  #   as the video key frame block.
  # - Audio blocks that have same absolute timecode as video blocks SHOULD be written before
  #   the video blocks.
  # See https://www.webmproject.org/docs/container/
  defp block_sorter({_id1, track1}, {_id2, track2}) do
    {time1, _data1, _track_number1, codec1} = track1.last_block
    {time2, _data2, _track_number2, codec2} = track2.last_block

    time1 < time2 or
      (time1 == time2 and
      (Codecs.type(codec1) == :audio and Codecs.type(codec2) == :video))
  end

  @impl true
  def handle_end_of_stream(Pad.ref(:input, id), _context, state) when state.active_tracks != 1 do
    {_track, state} = pop_in(state.tracks[id])
    state = update_in(state.active_tracks, & &1 - 1)
    state = update_in(state.expected_tracks, & &1 - 1)

    process_next_block_and_return(state)
  end

  @impl true
  def handle_end_of_stream(_pad_ref, _context, state) do
    # all blocks have now been processed
    cluster = Helper.serialize({:Cluster, state.cluster_acc})
    cues = Helper.serialize({:Cues, state.cues})
    _cues_segment_position = state.segment_position + byte_size(cluster)

    # TODO: Now I know the location of Cues so Seek can reference it.
    # Seek was the first serialized Segment element returned by the muxer and updating Seek requires rewriting data
    # If I choose to rewrite it I could just as well insert Cues at the beginning of the WebM file
    # This provides superior seeking speed when playing the file
    {{:ok, buffer: {:output, %Buffer{payload: cluster <> cues}}, end_of_stream: :output}, state}
  end
end
