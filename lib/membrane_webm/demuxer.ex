defmodule Membrane.WebM.Demuxer do
  @moduledoc """
  Filter element for demuxing WebM files.

  It receives a bytestream in WebM format and outputs the constituent tracks onto separate output pads.
  Streaming of each track occurs in chunks of up to 5 seconds an up to 5 mb of data.

  WebM files can contain many:
    - VP8 or VP9 video tracks
    - Opus or Vorbis audio tracks

  This module doesn't support Vorbis encoding.
  """
  use Membrane.Filter

  alias Membrane.{Buffer, Time, Pipeline.Action}
  alias Membrane.{Opus, RemoteStream, VP8, VP9}

  def_input_pad :input,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers,
    caps: {RemoteStream, content_format: :WEBM}

  def_output_pad :output,
    availability: :on_request,
    mode: :pull,
    caps: [VP8, VP9, Opus]

  defmodule State do
    @moduledoc false
    @type track_t :: audio_track_t | video_track_t

    @type audio_track_t :: %{
            codec: :opus,
            uid: non_neg_integer,
            active: boolean,
            channels: non_neg_integer
          }

    @type video_track_t :: %{
            codec: :vp8 | :vp9,
            uid: non_neg_integer,
            active: boolean,
            height: non_neg_integer,
            width: non_neg_integer,
            rate: Membrane.Time.t(),
            scale: non_neg_integer
          }

    @type t :: %__MODULE__{
            timestamp_scale: non_neg_integer,
            cache: list,
            output_active: boolean,
            tracks: %{(id :: non_neg_integer) => track_t},
            parser: %{required(:acc) => binary, required(:is_header_consumed) => boolean}
          }

    defstruct timestamp_scale: nil,
              cache: [],
              output_active: false,
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
  def handle_demand(Pad.ref(:output, _id), _size, :buffers, context, state) do
    # demuxer should output only if all pads are demanding

    output_active =
      context.pads
      |> Enum.filter(fn {id, _pad_data} -> id != :input end)
      |> Enum.all?(fn {_id, pad_data} -> pad_data.demand > 0 end)

    # reconsider output

    # actions = state.cache send demanded buffers...

    {:ok, %State{state | output_active: output_active}}
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
      Membrane.WebM.Parser.Helper.parse(
        unparsed,
        is_header_consumed,
        &Membrane.WebM.Schema.webm/1
      )

    {actions, state} = process_elements(parsed, state)

    {{:ok, actions ++ [{:demand, {:input, 1}}]},
     %State{state | parser: %{acc: unparsed, is_header_consumed: is_header_consumed}}}
  end

  @impl true
  def handle_end_of_stream(:input, _context, state) do
    actions =
      Enum.map(state.tracks, fn {id, _track_info} -> {:end_of_stream, Pad.ref(:output, id)} end)

    {{:ok, actions}, state}
  end

  @spec process_elements(list({atom, binary}), State.t()) :: {list(Action.t()), State.t()}
  def process_elements(elements_list, state) when is_list(elements_list) do
    elements_list
    |> Enum.reverse()
    |> Enum.reduce({[], state}, fn {element_name, data}, {actions, state} ->
      {new_actions, new_state} = process_elements(element_name, data, state)
      {actions ++ new_actions, new_state}
    end)
  end

  @spec process_elements(atom, binary, State.t()) :: {list(Action.t()), State.t()}
  def process_elements(element_name, data, state) do
    case element_name do
      :Info ->
        # scale of block timecodes in nanoseconds
        # should be 1_000_000 i.e. 1 ms
        {[], %State{state | timestamp_scale: data[:TimestampScale]}}

      :Tracks ->
        tracks = identify_tracks(data, state.timestamp_scale)
        actions = notify_about_new_track(tracks)
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
    Enum.map(buffers_list, fn {track_id, buffers} ->
      {:buffer, {Pad.ref(:output, track_id), buffers}}
    end)
  end

  defp notify_about_new_track(tracks) when is_map(tracks) do
    Enum.map(tracks, &notify_about_new_track/1)
  end

  defp notify_about_new_track(track) do
    {:notify, {:new_track, track}}
  end

  defp cluster_to_buffers(cluster, timestamp_scale) do
    timecode = cluster[:Timecode]

    cluster
    |> Keyword.get_values(:SimpleBlock)
    |> Enum.reduce([], fn block, acc ->
      [prepare_simple_block(block, timecode) | acc]
    end)
    |> Enum.group_by(& &1.track_number, &packetize(&1, timestamp_scale))
  end

  defp packetize(%{timecode: timecode, data: data}, timestamp_scale) do
    %Buffer{payload: data, dts: timecode * timestamp_scale, pts: timecode * timestamp_scale}
  end

  defp prepare_simple_block(block, cluster_timecode) do
    %{
      timecode: cluster_timecode + block.timecode,
      track_number: block.track_number,
      data: block.data
    }
  end

  defp identify_tracks(tracks, timestamp_scale) do
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
              scale: timestamp_scale
            }
        end

      {track[:TrackNumber], info}
    end
  end
end
