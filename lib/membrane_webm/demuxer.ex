defmodule Membrane.WebM.Demuxer do
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

  defmodule State do
    defstruct [:tracks, :timecodescale, :cache]
  end

  @impl true
  def handle_init(_) do
    {:ok, %State{cache: []}}
  end

  @impl true
  def handle_prepared_to_playing(_context, state) do
    {{:ok, demand: :input}, state}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _context, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_demand(
        Pad.ref(:output, _id),
        _size,
        :buffers,
        _context,
        %State{cache: _cache} = state
      ) do
    #! ignore?
    {:ok, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: {name, data}}, _context, state) do
    IO.puts("  Demuxer received #{name}")

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

        :Tags ->
          # :timer.sleep(1000)
          {[], state}

        :Cluster ->
          # :timer.sleep(1)
          buffers = to_buffers(data)
          actions = Enum.map(active_pads(buffers, state), &output/1)

          if actions != [] do
            IO.puts("    Demuxer sending Buffer")
          end

          to_cache = inactive_pads(buffers, state)
          cache = state.cache ++ to_cache
          {actions, %State{state | cache: cache}}

        _ ->
          {[], state}
      end

    actions = [{:demand, {:input, 1}} | actions]
    {{:ok, actions}, state}
  end

  def active_pads(buffers, state) do
    Enum.filter(buffers, fn {id, _data} -> state.tracks[id].active_pad end)
  end

  def inactive_pads(buffers, state) do
    Enum.filter(buffers, fn {id, _data} -> not state.tracks[id].active_pad end)
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, id), _context, %State{tracks: tracks} = state) do
    track_info = tracks[id]

    caps =
      case track_info.codec do
        :opus -> %Opus{channels: 2, self_delimiting?: false}
        # TODO :opus -> %Opus{channels: track_info.channels, self_delimiting?: false}
        :vp8 -> %RemoteStream{content_format: VP8, type: :packetized}
        :vp9 -> %RemoteStream{content_format: VP9, type: :packetized}
      end

    new_track_info = Map.put(track_info, :active_pad, true)
    new_tracks = Map.put(tracks, id, new_track_info)
    new_state = %State{state | tracks: new_tracks}

    # now that the pad is added all cached buffers intended for this pad can be sent
    to_send = active_pads(state.cache, new_state)
    new_cache = inactive_pads(state.cache, new_state)
    final_state = %State{new_state | cache: new_cache}

    {{:ok, [{:caps, {Pad.ref(:output, id), caps}}, output_to(to_send, id)]}, final_state}
  end

  defp send_notify_pads(tracks) when is_map(tracks) do
    Enum.map(tracks, &send_notify_pads/1)
  end

  # sends tuple {track_id, track_info}
  defp send_notify_pads(track) do
    {:notify, {:new_track, track}}
  end

  defp to_buffers(cluster) do
    cluster
    |> children(:SimpleBlock)
    |> Enum.map(&prepare_simple_block(&1, cluster[:Timecode]))
    |> List.flatten()
    |> Enum.reverse()
    |> Enum.group_by(& &1.track_number, &packetize/1)
  end

  def output_to(buffers, id) when is_list(buffers) do
    IO.puts("    Pad #{id} added. Demuxer sending cached Buffers")
    buffers = Enum.map(buffers, fn {_pad, buffers_list} -> buffers_list end) |> List.flatten()
    {:buffer, {Pad.ref(:output, id), buffers}}
  end

  def output({track_id, buffers}) do
    {:buffer, {Pad.ref(:output, track_id), buffers}}
  end

  defp prepare_simple_block(block, cluster_timecode) do
    %{
      timecode: cluster_timecode + block.timecode,
      track_number: block.track_number,
      data: block.data
    }
  end

  def identify_tracks(tracks, timecode_scale) do
    tracks = children(tracks, :TrackEntry)

    for track <- tracks, into: %{} do
      if track[:TrackType] == :audio do
        {
          track[:TrackNumber],
          %{
            codec: track[:CodecID],
            active_pad: false,
            channels: track[:Audio][:Channels]
          }
        }
      else
        {
          track[:TrackNumber],
          %{
            codec: track[:CodecID],
            active_pad: false,
            height: track[:Video][:PixelHeight],
            width: track[:Video][:PixelWidth],
            rate: Time.second(),
            scale: timecode_scale
          }
        }
      end
    end
  end

  def packetize(%{timecode: timecode, data: data}) do
    %Buffer{payload: data, metadata: %{timestamp: timecode * 1_000_000}}
  end

  def children(element_list, name) when is_list(element_list) do
    Keyword.get_values(element_list, name)
  end
end
