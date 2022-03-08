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
            # list of output buffers
            cache: list,
            output_active: boolean,
            tracks: %{(id :: non_neg_integer) => track_t},
            parser_acc: binary,
            current_timecode: integer
          }

    defstruct timestamp_scale: nil,
              cache: [],
              tracks_notified: false,
              output_active: false,
              tracks: %{},
              parser_acc: <<>>,
              current_timecode: nil
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
    # demuxer should output only as long as all pads are demanding
    demands =
      context.pads
      |> Enum.filter(fn {id, _pad_data} -> id != :input end)
      |> Enum.map(fn {{Membrane.Pad, :output, id}, pad_data} -> {id, pad_data.demand} end)
      |> Enum.into(%{})

    {to_send, to_cache} =
      if Enum.all?(state.tracks, fn {_id, track} -> track.active end) do
        # output buffers from cache as long as the destination pad demands it
        split_cache(state.cache, demands)
      else
        {[], state.cache}
      end

    buffer_actions =
      to_send
      # , &make_buffer/1)
      |> Enum.group_by(fn buffer -> buffer.metadata.track_number end)
      |> Enum.map(fn {track_number, buffers} ->
        {:buffer, {{Membrane.Pad, :output, track_number}, buffers}}
      end)

    # if no buffers remain in cache then demand further bytes from input
    if to_cache == [] do
      {{:ok, buffer_actions ++ [{:demand, :input}]}, %State{state | cache: to_cache}}
    else
      {{:ok, buffer_actions}, %State{state | cache: to_cache}}
    end
  end

  # defp make_buffer(block) do
  #   %Buffer{payload: block.data, dts: block.timestamp}
  # end

  # take blocks from cache until a block is encountered for which demand == 0
  defp split_cache(cache, demands) do
    {to_send, to_cache, _new_demands, _stop_output} =
      Enum.reduce(cache, {[], [], demands, false}, fn buffer,
                                                      {to_send, to_cache, demands, stop_output} ->
        if stop_output or demands[buffer.metadata.track_number] <= 0 do
          {to_send, [buffer | to_cache], demands, true}
        else
          {[buffer | to_send], to_cache,
           update_in(demands[buffer.metadata.track_number], &(&1 - 1)), false}
        end
      end)

    {to_send, to_cache}
  end

  # defp send_demanded_buffers(context, state) do
  #   {buffer_actions, new_cache} =
  #     Enum.reduce(context.pads, {[], state.cache},
  #     fn {{id, pad_data}, {actions, cache}} ->
  #     {buffer_count, buffers} = cache[id]
  #     cond do
  #       buffer_count > 0 and buffer_count >= pad_data.demand ->
  #         {buffers, rest} = Qex.split(buffers, buffer_count)
  #         new_cache = Map.put(cache, id, {buffer_count - pad_data.demand, rest})
  #         action = {:buffer, {Pad.ref(:output, id), Enum.to_list(buffers)}}
  #         {[action | actions], new_cache}
  #       buffer_count > 0 and buffer_count < pad_data.demand ->
  #         new_cache = Map.put(cache, id, {0, Qex.new})
  #         action = {:buffer, {Pad.ref(:output, id), Enum.to_list(buffers)}}
  #         {[action | actions], new_cache}
  #       buffer_count == 0 ->
  #         {actions, cache}
  #     end
  #   end)
  #   {buffer_actions, %State{state | cache: new_cache}}
  # end

  # defp send_buffers_for_active_tracks(state) do
  #   actions = state.cache
  #   |> Enum.filter(fn {id, _buffers} -> state.tracks[id].active end)
  #   |> Enum.map(fn {id, buffers} -> {:buffer, {Pad.ref(:output, id), Enum.to_list(buffers)}} end)
  #   new_state = %State{state | cache: Enum.map(state.cache, fn {id, _qex} -> {id, Qex.new} end)}
  #   {actions, new_state}
  # end

  @impl true
  def handle_process(
        :input,
        %Buffer{payload: payload},
        _context,
        %State{parser_acc: acc} = state
      ) do
    unparsed = acc <> payload

    {parsed, unparsed} =
      Membrane.WebM.Parser.Helper.parse(
        unparsed,
        &Membrane.WebM.Schema.webm/1
      )

    {actions, state} = process_elements(parsed, state)

    # if even one element can't be parsed return demand: :input
    if parsed == [] or not state.tracks_notified do
      {{:ok, demand: :input}, %State{state | parser_acc: unparsed}}
    else
      {{:ok, actions}, %State{state | parser_acc: unparsed}}
    end
  end

  @impl true
  def handle_end_of_stream(:input, _context, state) do
    actions =
      Enum.map(state.tracks, fn {id, _track_info} -> {:end_of_stream, Pad.ref(:output, id)} end)

    {{:ok, actions}, state}
  end

  @spec process_elements(list({atom, binary}), State.t()) :: {list(Action.t()), State.t()}
  defp process_elements(elements_list, state) do
    elements_list
    # FIXME: don't reverse and prepend everything to lists => don't use Qex as cache
    |> Enum.reverse()
    |> Enum.reduce({[], state}, fn {element_name, data}, {actions, state} ->
      {new_actions, new_state} = process_element(element_name, data, state)
      {actions ++ new_actions, new_state}
    end)
  end

  @spec process_element(atom, binary, State.t()) :: {list(Action.t()), State.t()}
  defp process_element(element_name, data, state) do
    IO.puts(element_name)

    case element_name do
      :Info ->
        # scale of block timecodes in nanoseconds
        # should be 1_000_000 i.e. 1 ms
        {[], %State{state | timestamp_scale: data[:TimestampScale]}}

      :Tracks ->
        tracks = identify_tracks(data, state.timestamp_scale)
        actions = notify_about_new_track(tracks)
        {actions, %State{state | tracks: tracks, tracks_notified: true}}

      :Timecode ->
        {[], %State{state | current_timecode: data}}

      :SimpleBlock ->
        buffer = %Buffer{
          payload: data.data,
          dts: (state.current_timecode + data.timecode) * state.timestamp_scale,
          metadata: %{track_number: data.track_number}
        }
        IO.inspect((state.current_timecode + data.timecode) * state.timestamp_scale)
        {[], %State{state | cache: [buffer | state.cache]}}

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

    new_state = %State{state | tracks: put_in(tracks[id].active, true)}

    {{:ok, caps: {Pad.ref(:output, id), caps}, redemand: Pad.ref(:output, id)}, new_state}
  end

  # defp prepare_output_buffers(buffers_list) do
  #   Enum.map(Enum.to_list(buffers_list), fn {track_id, buffers} ->
  #     {:buffer, {Pad.ref(:output, track_id), buffers}}
  #   end)
  # end

  defp notify_about_new_track(tracks) do
    Enum.map(tracks, fn track -> {:notify, {:new_track, track}} end)
  end

  # defp cluster_to_buffers(cluster, timestamp_scale) do
  #   timecode = cluster[:Timecode]

  #   cluster
  #   |> Keyword.get_values(:SimpleBlock)
  #   |> Enum.reduce([], fn block, acc ->
  #     [prepare_simple_block(block, timecode) | acc]
  #   end)
  #   |> Enum.group_by(& &1.track_number, &packetize(&1, timestamp_scale))
  # end

  # defp packetize(%{timecode: timecode, data: data}, timestamp_scale) do
  #   %Buffer{payload: data, dts: timecode * timestamp_scale, pts: timecode * timestamp_scale}
  # end

  # defp prepare_simple_block(block, cluster_timecode) do
  #   %{
  #     timecode: cluster_timecode + block.timecode,
  #     track_number: block.track_number,
  #     data: block.data
  #   }
  # end

  defp identify_tracks(tracks, timestamp_scale) do
    tracks = Keyword.get_values(tracks, :TrackEntry)

    for track <- tracks, into: %{} do
      info =
        case track[:TrackType] do
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
