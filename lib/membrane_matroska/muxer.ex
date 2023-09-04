defmodule Membrane.Matroska.Muxer do
  @moduledoc """
  Filter element for muxing Matroska files.

  It accepts an arbitrary number of Opus, VP8, VP9 or H264 streams and outputs a bytestream in Matroska format containing those streams.

  Muxer guidelines
  https://www.matroskaproject.org/docs/container/
  """
  use Bunch
  use Membrane.Filter

  require Membrane.H264
  alias Membrane.{Buffer, H264, Matroska, Opus, RemoteStream, VP8, VP9}
  alias Membrane.Matroska.Parser.Codecs
  alias Membrane.Matroska.Serializer
  alias Membrane.Matroska.Serializer.Helper

  def_options title: [
                spec: String.t(),
                default: "Membrane Matroska file",
                description: "Title to be used in the `Segment/Info/Title` element"
              ],
              date: [
                spec: nil | DateTime.t(),
                default: nil,
                description: "Datetime which will be store in  the `Segment/Info/DateUTC` element.
                  Default value is the time of initialization of this element."
              ]

  def_input_pad :input,
    availability: :on_request,
    mode: :pull,
    demand_unit: :buffers,
    accepted_format:
      any_of(
        %H264{nalu_in_metadata?: true, stream_structure: structure} when H264.is_avc(structure),
        %Opus{self_delimiting?: false, channels: channels} when channels in [1, 2],
        %RemoteStream{content_format: format, type: :packetized} when format in [VP8, VP9]
      )

  def_output_pad :output,
    availability: :always,
    mode: :pull,
    accepted_format: %RemoteStream{content_format: Matroska}

  # 5 mb
  @cluster_bytes_limit 5_242_880
  @cluster_time_limit Membrane.Time.seconds(5)
  @timestamp_scale Membrane.Time.millisecond()

  defmodule State do
    @moduledoc false
    use Bunch.Access

    defstruct tracks: %{},
              segment_position: 0,
              expected_tracks_ordering: %{},
              active_tracks_cnt: 0,
              cluster_acc: Helper.serialize({:Timecode, 0}),
              cluster_time: nil,
              cluster_size: 0,
              cues: [],
              time_min: 0,
              time_max: 0,
              options: %{}
  end

  @impl true
  def handle_init(_ctx, options) do
    options = options |> Map.put(:duration, 0) |> Map.put(:clusters_size, 0)
    {[], %State{options: options}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, id), context, state) when context.playback != :playing do
    expected_tracks_ordering =
      Map.put(state.expected_tracks_ordering, id, map_size(state.expected_tracks_ordering) + 1)

    {[], %State{state | expected_tracks_ordering: expected_tracks_ordering}}
  end

  @impl true
  def handle_pad_added(_pad, _ctx, _state) do
    raise "Can't add new input pads to muxer in state :playing!"
  end

  @impl true
  def handle_stream_format(Pad.ref(:input, id), _stream_format, _ctx, state)
      when is_map_key(state.tracks, id) do
    {[], state}
  end

  @impl true
  def handle_stream_format(Pad.ref(:input, id), stream_format, _ctx, state) do
    codec =
      case stream_format do
        %RemoteStream{content_format: VP8} ->
          :vp8

        %RemoteStream{content_format: VP9} ->
          :vp9

        %Opus{} ->
          :opus

        %H264{} ->
          :h264

        format when is_struct(format) ->
          raise "unsupported stream format #{inspect(format.__struct__)}"

        _other ->
          raise "unsupported stream format #{inspect(stream_format)}"
      end

    state = update_in(state.active_tracks_cnt, &(&1 + 1))
    type = Codecs.type(codec)

    track = %{
      track_number: state.expected_tracks_ordering[id],
      id: id,
      codec: codec,
      stream_format: stream_format,
      type: type,
      cached_block: nil,
      offset: nil,
      which_timestamp: nil,
      active?: true
    }

    state = put_in(state.tracks[id], track)

    if state.active_tracks_cnt == map_size(state.expected_tracks_ordering) do
      demands = Enum.map(state.tracks, fn {id, _track_data} -> {:demand, Pad.ref(:input, id)} end)

      stream_format = [
        stream_format: {:output, %RemoteStream{content_format: Matroska, type: :bytestream}}
      ]

      {stream_format ++ demands, state}
    else
      {[], state}
    end
  end

  # demand all tracks for which the last frame is not cached
  @impl true
  def handle_demand(:output, _size, :buffers, _ctx, state)
      when map_size(state.expected_tracks_ordering) == state.active_tracks_cnt do
    demands = get_demands(state)

    if demands == [] do
      {state, _maybe_cluster} = process_next_block(state)
      {get_demands(state), state}
    else
      {demands, state}
    end
  end

  @impl true
  def handle_demand(:output, _size, :buffers, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_process(pad_ref, buffer, _ctx, state) do
    state = ingest_buffer(state, pad_ref, buffer)
    process_next_block_or_redemand(state)
  end

  @impl true
  def handle_end_of_stream(Pad.ref(:input, id), _ctx, state) when state.active_tracks_cnt != 1 do
    state = update_in(state.active_tracks_cnt, &(&1 - 1))
    {_track_number, state} = pop_in(state, [:expected_tracks_ordering, id])
    state = put_in(state.tracks[id][:active?], false)
    # {_track, state} = pop_in(state.tracks[id])

    process_next_block_or_redemand(state)
  end

  @impl true
  def handle_end_of_stream(Pad.ref(:input, _id), _ctx, state) do
    if Enum.any?(state.tracks, fn {_track_id, track} -> track.cached_block != nil end) do
      raise "Not empty tracks"
    end

    cluster = Helper.serialize({:Cluster, state.cluster_acc})
    clusters_size = state.segment_position + byte_size(cluster)
    state = put_in(state.options.clusters_size, clusters_size)
    duration = (state.time_max - state.time_min) / @timestamp_scale
    state = put_in(state.options.duration, duration)

    {segment_position, matroska_header} =
      Serializer.Matroska.serialize_matroska_header(state.tracks, state.options)

    cues = update_cues_postion(state.cues, segment_position)
    cues = Helper.serialize({:Cues, cues})
    buffer_cluster = %Buffer{payload: cluster <> cues}
    seek_event = %Membrane.File.SeekSinkEvent{position: 0, insert?: true}

    {
      [
        buffer: {:output, buffer_cluster},
        event: {:output, seek_event},
        buffer: {:output, %Buffer{payload: matroska_header}},
        end_of_stream: :output
      ],
      state
    }
  end

  defp update_cues_postion(cues, header_size) do
    Enum.map(cues, fn {:CuePoint, cue} ->
      cue = Keyword.update!(cue, :CueClusterPosition, &(&1 + header_size))
      {:CuePoint, cue}
    end)
  end

  defp ingest_buffer(state, Pad.ref(:input, id), %Buffer{} = buffer) do
    # update last timestamp

    track = state.tracks[id]

    track =
      if track.offset == nil do
        which_timestamp = if buffer.pts == nil, do: :dts, else: :pts
        offset = buffer.pts || buffer.dts
        %{track | which_timestamp: which_timestamp, offset: offset}
      else
        track
      end

    state = put_in(state.tracks[id], track)
    timestamp = div(Buffer.get_dts_or_pts(buffer) - track.offset, @timestamp_scale)

    state = update_in(state.time_min, &min(timestamp, &1))
    state = update_in(state.time_max, &max(timestamp, &1))
    # cache last block
    block = {timestamp, buffer, state.tracks[id].track_number, state.tracks[id].codec}

    put_in(state.tracks[id].cached_block, block)
  end

  # one block is cached for each track
  # takes the block that should come next and appends it to current cluster or creates a new cluster for it and outputs the current cluster
  defp process_next_block(state) do
    state
    |> pop_next_block()
    |> step_cluster()
  end

  defp process_next_block_and_return(state) do
    {state, maybe_cluster} = process_next_block(state)

    case maybe_cluster do
      <<>> ->
        {[redemand: :output], state}

      serialized_payload ->
        {[buffer: {:output, %Buffer{payload: serialized_payload}}, redemand: :output], state}
    end
  end

  defp pop_next_block(state) do
    # find next block
    tracks =
      Enum.filter(state.tracks, fn {_track_id, track} ->
        track.active? or track.cached_block != nil
      end)

    sorted = Enum.sort(tracks, &block_sorter/2)
    {id, track} = hd(sorted)
    block = track.cached_block
    # delete the block from state
    state = put_in(state.tracks[id].cached_block, nil)
    {state, block, state.tracks[id]}
  end

  # https://www.matroska.org/technical/cues.html
  defp add_cluster_cuepoint(state, track_number) do
    new_cue =
      {:CuePoint,
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
  # Matroska Muxer Guidelines https://www.matroskaproject.org/docs/container/
  defp step_cluster(
         {%State{
            cluster_acc: current_cluster_acc,
            cluster_time: cluster_time,
            cluster_size: cluster_size
          } = state, {_absolute_time, data, track_number, type} = block, track}
       ) do
    absolute_time = get_proper_timestamp(data, track)

    cluster_time = if cluster_time == nil, do: absolute_time, else: cluster_time
    relative_time = absolute_time - cluster_time

    # 32767 is max valid value of a simpleblock timecode (max signed_int16)
    if relative_time * @timestamp_scale > Membrane.Time.milliseconds(32_767) do
      IO.warn("Simpleblock timecode overflow. Still writing but some data will be lost.")
    end

    begin_new_cluster =
      cluster_size >= @cluster_bytes_limit or
        relative_time * @timestamp_scale >= @cluster_time_limit or
        Codecs.is_video_keyframe?(block)

    if begin_new_cluster do
      timecode = {:Timecode, absolute_time}
      simple_block = {:SimpleBlock, {0, data, track_number, type}}
      new_cluster = Helper.serialize([timecode, simple_block])

      state =
        if Codecs.type(type) == :video do
          add_cluster_cuepoint(
            %State{
              state
              | cluster_acc: new_cluster,
                cluster_time: absolute_time,
                cluster_size: byte_size(new_cluster)
            },
            track_number
          )
        else
          %State{
            state
            | cluster_acc: new_cluster,
              cluster_time: absolute_time,
              cluster_size: byte_size(new_cluster)
          }
        end

      if current_cluster_acc == Helper.serialize({:Timecode, 0}) do
        {state, <<>>}
      else
        serialized_cluster = Helper.serialize({:Cluster, current_cluster_acc})
        state = update_in(state.segment_position, &(&1 + byte_size(serialized_cluster)))

        # return serialized cluster
        {state, serialized_cluster}
      end
    else
      simple_block = {:SimpleBlock, {relative_time, data, track_number, type}}
      serialized_block = Helper.serialize(simple_block)
      state = update_in(state.cluster_acc, &(&1 <> serialized_block))
      state = update_in(state.cluster_size, &(&1 + byte_size(serialized_block)))
      state = put_in(state.cluster_time, cluster_time)

      {state, <<>>}
    end
  end

  defp get_proper_timestamp(buffer, track) do
    buffer_timestamp = Map.get(buffer, track.which_timestamp)

    (buffer_timestamp - track.offset)
    |> div(@timestamp_scale)
  end

  defp enough_cached_blocks?(track) do
    track.cached_block == nil and track.active?
  end

  # Blocks are written in timestamp order.
  defp block_sorter({_id1, track1}, {_id2, track2}) do
    block_track1 = track1.cached_block
    block_track2 = track2.cached_block

    {start_time1, _data1, _track_number1, codec1} = block_track1
    {start_time2, _data2, _track_number2, codec2} = block_track2

    start_time1 < start_time2 or
      (start_time1 == start_time2 and
         (Codecs.type(codec1) == :video and Codecs.type(codec2) == :audio))
  end

  defp process_next_block_or_redemand(state) do
    if Enum.any?(state.tracks, fn {_id, track} -> enough_cached_blocks?(track) end) do
      {[redemand: :output], state}
    else
      process_next_block_and_return(state)
    end
  end

  defp get_demands(state) do
    state.tracks
    |> Enum.filter(fn {_id, track} -> enough_cached_blocks?(track) end)
    |> Enum.map(fn {id, _info} -> {:demand, Pad.ref(:input, id)} end)
  end
end
