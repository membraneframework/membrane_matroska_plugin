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

  alias Membrane.{Buffer, RemoteStream, Time}
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

  # nanoseconds in milisecond # TODO: is this right?
  @time_base 1_000_000

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
  def handle_process(:input, %Buffer{payload: data, metadata: %{name: name}}, _context, state) do
    {actions, state} =
      case name do
        :Info ->
          # scale of block timecodes in nanoseconds
          # should be 1_000_000 i.e. 1 ms
          {[], %State{state | timecodescale: data[:TimecodeScale]}}

        :Tracks ->
          tracks = identify_tracks(data, state.timecodescale)
          actions = send_notify_pads(tracks)
          {actions, %State{state | tracks: tracks}}

        :Cluster ->
          {active, inactive} =
            data
            |> cluster_to_buffers
            |> Enum.split_with(fn {id, _buffer} -> state.tracks[id].active end)

          {output(active), %State{state | cache: state.cache ++ inactive}}

        _ ->
          {[], state}
      end

    {{:ok, [{:demand, {:input, 1}} | actions]}, state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, id), _context, %State{tracks: tracks} = state) do
    caps =
      case tracks[id].codec do
        :opus -> %Opus{channels: 2, self_delimiting?: false}
        # TODO: :opus -> %Opus{channels: track_info.channels, self_delimiting?: false}
        # TODO: it's not a remote stream
        :vp8 -> %RemoteStream{content_format: VP8, type: :packetized}
        # TODO: as above
        :vp9 -> %RemoteStream{content_format: VP9, type: :packetized}
      end

    # now that the pad is added all cached buffers destined for this pad can be sent
    {active, inactive} = Enum.split_with(state.cache, fn {pad_id, _} -> pad_id == id end)
    actions = [{:caps, {Pad.ref(:output, id), caps}} | output(active)]
    new_state = %State{state | tracks: activate_track(id, tracks), cache: inactive}

    {{:ok, actions}, new_state}
  end

  defp activate_track(id, tracks) do
    new_track_info = Map.put(tracks[id], :active, true)
    Map.put(tracks, id, new_track_info)
  end

  defp output(buffers_list) when is_list(buffers_list) do
    Enum.map(buffers_list, &output/1)
  end

  defp output({track_id, buffers}) do
    {:buffer, {Pad.ref(:output, track_id), buffers}}
  end

  defp send_notify_pads(tracks) when is_map(tracks) do
    Enum.map(tracks, &send_notify_pads/1)
  end

  # sends tuple `{track_id, track_info} = track`
  defp send_notify_pads(track) do
    {:notify, {:new_track, track}}
  end

  defp cluster_to_buffers(cluster) do
    cluster
    |> Keyword.get_values(:SimpleBlock)
    # we use reduce instead of map to restore the correct block order (which the parser reversed by prepending elements)
    |> Enum.reduce([], fn block, acc ->
      [prepare_simple_block(block, cluster[:Timecode]) | acc]
    end)
    |> List.flatten()
    |> Enum.group_by(& &1.track_number, &packetize/1)
  end

  defp packetize(%{timecode: timecode, data: data}) do
    %Buffer{payload: data, pts: timecode * @time_base}
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
