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

  # nanoseconds in milisecond # TODO is this right?
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

  # FIXME ignoring for now
  @impl true
  def handle_demand(Pad.ref(:output, _id), _size, :buffers, _context, state) do
    {:ok, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: data, metadata: %{name: name}}, _context, state) do
    # IO.puts("  Demuxer received #{name}")

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
          # TODO You could create sending buffer's action and cache the buffers for inactive pads all at one pass. Just create maybe_send_buffers function where you will reduce the buffers and state.
          buffers = cluster_to_buffers(data)
          actions = Enum.map(active(buffers, state), &output/1)

          if actions != [] do
            # IO.puts("    Demuxer sending Buffer")
          end

          to_cache = inactive(buffers, state)
          new_cache = state.cache ++ to_cache
          {actions, %State{state | cache: new_cache}}

        _ ->
          {[], state}
      end

    {{:ok, [{:demand, {:input, 1}} | actions]}, state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, id), _context, %State{tracks: tracks} = state) do
    track_info = Map.fetch!(tracks, id)

    caps =
      case track_info.codec do
        :opus -> %Opus{channels: 2, self_delimiting?: false}
        # TODO :opus -> %Opus{channels: track_info.channels, self_delimiting?: false}
        # TODO it's not a remote stream
        :vp8 -> %RemoteStream{content_format: VP8, type: :packetized}
        # TODO as above
        :vp9 -> %RemoteStream{content_format: VP9, type: :packetized}
      end

    new_track_info = Map.put(track_info, :active, true)
    new_tracks = Map.put(tracks, id, new_track_info)
    new_state = %State{state | tracks: new_tracks}

    # now that the pad is added all cached buffers intended for this pad can be sent
    # TODO Again, all of this should be a single functions that will return cached buffers for given pad and return updated state. You are hand crafting everything which is less readable.
    to_send = active(state.cache, new_state)
    new_cache = inactive(state.cache, new_state)
    final_state = %State{new_state | cache: new_cache}
    buffer_actions = Enum.map(to_send, &output/1)
    caps_action = {:caps, {Pad.ref(:output, id), caps}}
    actions = [caps_action | buffer_actions]

    # IO.puts("    Pad #{id} added. Demuxer sending cached Buffers")
    {{:ok, actions}, final_state}
  end

  defp output({track_id, buffers}) do
    {:buffer, {Pad.ref(:output, track_id), buffers}}
  end

  # returns buffers intended for pads that are currently active
  defp active(buffers, state) do
    Enum.filter(buffers, fn {id, _data} -> state.tracks[id].active end)
  end

  defp inactive(buffers, state) do
    Enum.filter(buffers, fn {id, _data} -> not state.tracks[id].active end)
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
    |> Enum.map(&prepare_simple_block(&1, cluster[:Timecode]))
    |> List.flatten()
    # TODO why reverse?
    |> Enum.reverse()
    |> Enum.group_by(& &1.track_number, &packetize/1)
  end

  defp packetize(%{timecode: timecode, data: data}) do
    %Buffer{payload: data, metadata: %{timestamp: timecode * @time_base}}
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
      if track[:TrackType] == :audio do
        {
          track[:TrackNumber],
          %{
            codec: track[:CodecID],
            active: false,
            channels: track[:Audio][:Channels]
          }
        }
      else
        {
          track[:TrackNumber],
          %{
            codec: track[:CodecID],
            active: false,
            height: track[:Video][:PixelHeight],
            width: track[:Video][:PixelWidth],
            rate: Time.second(),
            scale: timecode_scale
          }
        }
      end
    end
  end
end
