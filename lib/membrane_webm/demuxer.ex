defmodule Membrane.WebM.Demuxer do
  @moduledoc """
  Module for demuxing WebM files.

  It expects to receive parsed WebM elements provided by `Membrane.WebM.Parser` and outputs the constituent tracks onto separate output pads.
  Streaming of each track occurs in chunks of up to 5 seconds of data.

  WebM files can contain many:
    - VP8 or VP9 video tracks
    - Opus or Vorbis audio tracks

  This module supports all encodings except Vorbis.
  """
  use Membrane.Filter

  alias Membrane.{Buffer, Time}
  alias Membrane.{Opus, VP8, VP9}

  def_input_pad :input,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers,
    caps: :any

  def_output_pad :output,
    availability: :on_request,
    mode: :pull,
    caps: :any

  defmodule State do
    defstruct timecodescale: nil, cache: [], tracks: %{}
  end

  @impl true
  def handle_init(_) do
    {:ok, %State{}}
  end

  @impl true
  def handle_prepared_to_playing(_context, state) do
    {{:ok, demand: :input}, state}
  end

  # FIXME: ignoring for now
  @impl true
  def handle_demand(Pad.ref(:output, _id), _size, :buffers, _context, state) do
    {:ok, state}
  end

  @impl true
  def handle_process(
        :input,
        %Buffer{payload: data, metadata: %{webm: %{element_name: element_name}}},
        _context,
        state
      ) do
    {actions, state} =
      case element_name do
        :Info ->
          # scale of block timecodes in nanoseconds
          # should be 1_000_000 i.e. 1 ms
          {[], %State{state | timecodescale: data[:TimecodeScale]}}

        :Tracks ->
          tracks = identify_tracks(data, state.timecodescale)
          actions = notify_new_track(tracks)
          {actions, %State{state | tracks: tracks}}

        :Cluster ->
          {active, inactive} =
            data
            |> cluster_to_buffers(state.timecodescale)
            |> Enum.split_with(fn {id, _buffer} -> state.tracks[id].active end)

          {prepare_output_buffers(active), %State{state | cache: state.cache ++ inactive}}

        _ ->
          {[], state}
      end

    {{:ok, [{:demand, {:input, 1}} | actions]}, state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, id), _context, %State{tracks: tracks} = state) do
    track = tracks[id]

    caps =
      case track.codec do
        # TODO: :opus -> %Opus{channels: track_info.channels, self_delimiting?: false}
        :opus ->
          %Opus{channels: 2, self_delimiting?: false}

        :vp8 ->
          %VP8{width: track.width, height: track.height}

        :vp9 ->
          %VP9{width: track.width, height: track.height}
      end

    # now that the pad is added all cached buffers destined for this pad can be sent
    {track_buffers, other_buffers} =
      Enum.split_with(state.cache, fn {pad_id, _buffer} -> pad_id == id end)

    actions = [{:caps, {Pad.ref(:output, id), caps}} | prepare_output_buffers(track_buffers)]

    new_state = %State{
      state
      | tracks: update_in(tracks[id].active, fn _ -> true end),
        cache: other_buffers
    }

    {{:ok, actions}, new_state}
  end

  defp prepare_output_buffers(buffers_list) when is_list(buffers_list) do
    Enum.map(buffers_list, &prepare_output_buffers/1)
  end

  defp prepare_output_buffers({track_id, buffers}) do
    {:buffer, {Pad.ref(:output, track_id), buffers}}
  end

  defp notify_new_track(tracks) when is_map(tracks) do
    Enum.map(tracks, &notify_new_track/1)
  end

  # sends tuple `{track_id, track_info} = track`
  defp notify_new_track(track) do
    {:notify, {:new_track, track}}
  end

  defp cluster_to_buffers(cluster, timecode_scale) do
    timecode = cluster[:Timecode]

    cluster
    |> Keyword.get_values(:SimpleBlock)
    |> Enum.reduce([], fn block, acc ->
      [prepare_simple_block(block, timecode) | acc]
    end)
    |> Enum.group_by(& &1.track_number, &packetize(&1, timecode_scale))
  end

  defp packetize(%{timecode: timecode, data: data}, timecode_scale) do
    %Buffer{payload: data, pts: timecode * timecode_scale}
  end

  defp prepare_simple_block(block, cluster_timecode) do
    %{
      timecode: cluster_timecode + block.timecode,
      track_number: block.track_number,
      data: block.data
    }
  end

  defp identify_tracks(tracks, timecode_scale) do
    tracks = Keyword.get_values(tracks, :TrackEntry)

    for track <- tracks, into: %{} do
      info =
        case track[:TrackType] do
          :audio ->
            %{
              codec: track[:CodecID],
              active: false,
              channels: track[:Audio][:Channels]
            }

          :video ->
            %{
              codec: track[:CodecID],
              active: false,
              height: track[:Video][:PixelHeight],
              width: track[:Video][:PixelWidth],
              rate: Time.second(),
              scale: timecode_scale
            }
        end

      {track[:TrackNumber], info}
    end
  end
end
