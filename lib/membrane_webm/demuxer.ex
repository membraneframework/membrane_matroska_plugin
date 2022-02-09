defmodule Membrane.WebM.Demuxer do
  @moduledoc """
  Module for demuxing WebM files.

  It receives a bytestream containing a WebM file and outputs the constituent tracks onto separate output pads.
  Streaming of each track occurs in chunks of up to 5 seconds of data.

  WebM files can contain many:
    - VP8 or VP9 video tracks
    - Opus or Vorbis audio tracks

  This module doesn't support Vorbis encoding.
  """
  use Membrane.Filter

  alias Membrane.{Buffer, Time, Pipeline.Action}
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
    @moduledoc false

    @type t :: %__MODULE__{}

    defstruct timestamp_scale: nil,
              cache: [],
              tracks: %{},
              parser: %{acc: <<>>, is_header_consumed: false}
  end

  @impl true
  def handle_init(_options) do
    {:ok, %State{}}
  end

  @impl true
  def handle_prepared_to_playing(_context, state) do
    {{:ok, demand: :input}, state}
  end

  @impl true
  def handle_demand(Pad.ref(:output, _id), _size, :buffers, _context, state) do
    {:ok, state}
  end

  @impl true
  def handle_process(
        :input,
        %Buffer{payload: payload},
        _context,
        %State{parser: %{acc: acc, is_header_consumed: is_header_consumed}} = state
      ) do
    unparsed = acc <> payload

    {parsed, unparsed, is_header_consumed} =
      Membrane.WebM.Parser.Helper.parse(unparsed, is_header_consumed)

    {actions, state} = process_element(parsed, state)

    {{:ok, [{:demand, {:input, 1}} | actions]},
     %State{state | parser: %{acc: unparsed, is_header_consumed: is_header_consumed}}}
  end

  @spec process_element(list({atom, binary}), State.t()) :: {list(Action.t()), State.t()}
  def process_element(elements_list, state) when is_list(elements_list) do
    elements_list
    |> Enum.reverse()
    |> Enum.reduce({[], state}, fn {element_name, data}, {actions, state} ->
      {new_actions, new_state} = process_element(element_name, data, state)
      {actions ++ new_actions, new_state}
    end)
  end

  @spec process_element(atom, binary, State.t()) :: {list(Action.t()), State.t()}
  def process_element(element_name, data, state) do
    case element_name do
      :Info ->
        # scale of block timecodes in nanoseconds
        # should be 1_000_000 i.e. 1 ms
        {[], %State{state | timestamp_scale: data[:TimestampScale]}}

      :Tracks ->
        tracks = identify_tracks(data, state.timestamp_scale)
        actions = notify_new_track(tracks)
        {actions, %State{state | tracks: tracks}}

      :Cluster ->
        {active, inactive} =
          data
          |> cluster_to_buffers(state.timestamp_scale)
          |> Enum.split_with(fn {id, _buffer} -> state.tracks[id].active end)

        {prepare_output_buffers(active), %State{state | cache: state.cache ++ inactive}}

      _other_element ->
        {[], state}
    end
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, id), _context, %State{tracks: tracks} = state) do
    track = tracks[id]

    caps =
      case track.codec do
        :opus ->
          %Opus{channels: track.channels, self_delimiting?: false}

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
      | tracks: put_in(tracks[id].active, true),
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
    %Buffer{payload: data, dts: timecode * timecode_scale, pts: timecode * timecode_scale}
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
          # The TrackUID SHOULD be kept the same when making a direct stream copy to another file.

          :audio ->
            %{
              codec: track[:CodecID],
              uid: track[:TrackUID],
              active: false,
              channels: track[:Audio][:Channels]
            }

          :video ->
            %{
              codec: track[:CodecID],
              uid: track[:TrackUID],
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
