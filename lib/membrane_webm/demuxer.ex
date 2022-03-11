defmodule Membrane.WebM.Demuxer do
  @moduledoc """
  Filter element for demuxing WebM files.

  Receives a bytestream in WebM file format as input and outputs the constituent tracks of that file
  onto seperate pads.

  Works in three phases:

  - :reading_header
    Demands and parses the beginning bytes of the WebM file describing it's contents and sends:
    `{:notify, {:new_track, {track_id, track_t}}}`
    message to the parent pipeline for every track contained in the file.

  - :notified_about_content
    Pauses and waits for an output pad to be linked for every track in the file.
    Expects elements to be linked via pad `Pad.ref(:output, track_id)`.

  - :all_outputs_linked
    Once all the expected output pads are linked it starts streaming the file's media with speed adjusted
    to the slowest of the output elements i.e. pausing when demands on that element's pad equals 0.

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
            blocked?: boolean,
            demands: %{(pad_id :: non_neg_integer) => demands_for_pad :: non_neg_integer},
            # actions that can be sent from the current callback
            actions: Qex.t(Action.t()),
            # actions that must be sent later
            cache: Qex.t(Action.t()),
            phase: :reading_header | :notified_about_content | :all_outputs_linked,
            tracks: %{(pad_id :: non_neg_integer) => track_t},
            parser_acc: binary,
            current_timecode: integer
          }

    defstruct timestamp_scale: nil,
              blocked?: true,
              demands: %{},
              actions: Qex.new(),
              cache: Qex.new(),
              phase: :reading_header,
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
  def handle_end_of_stream(:input, _context, state) do
    actions =
      Enum.map(state.tracks, fn {id, _track_info} -> {:end_of_stream, Pad.ref(:output, id)} end)

    {{:ok, actions}, state}
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

    state = %State{state | tracks: put_in(tracks[id].active, true)}

    state =
      if Enum.all?(state.tracks, fn {_k, v} -> v.active end) do
        %State{state | phase: :all_outputs_linked}
      else
        state
      end

    {{:ok, caps: {Pad.ref(:output, id), caps}}, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: bytes}, context, state) do
    unparsed = state.parser_acc <> bytes
    {parsed, unparsed} = parse(unparsed)

    state =
      %State{state | parser_acc: unparsed}
      |> update_demands(context)
      |> process_elements(parsed)

    # if even one element couldn't be parsed then demand more data and try again
    if parsed == [] or state.phase == :reading_header do
      {{:ok, demand: :input}, state}
    else
      state
      |> demand_if_not_blocked()
      |> send_actions()
    end
  end

  @impl true
  def handle_demand(Pad.ref(:output, _id), _size, :buffers, context, state) do
    if state.phase == :all_outputs_linked and state.blocked? do
      # reconsider if cached buffers can now be sent
      state
      |> update_demands(context)
      |> reclassify_cached_buffer_actions()
      |> demand_if_not_blocked()
      |> send_actions()
    else
      {:ok, state}
    end
  end

  defp process_elements(state, elements_list) do
    # TODO: make parser helper return Qex of elements instead of list
    elements_list = Enum.reverse(elements_list)
    Enum.reduce(elements_list, state, &process_element/2)
  end

  defp process_element({element_name, data} = _element, state) do
    case element_name do
      :Info ->
        # scale of block timecodes in nanoseconds
        # should be 1_000_000 i.e. 1 ms
        %State{state | timestamp_scale: data[:TimestampScale]}

      :Tracks ->
        tracks = identify_tracks(data, state.timestamp_scale)
        actions = notify_about_new_tracks(tracks)

        %State{
          state
          | actions: Qex.join(actions, state.actions),
            tracks: tracks,
            phase: :notified_about_content
        }

      :Timecode ->
        %State{state | current_timecode: data}

      :SimpleBlock ->
        buffer_action =
          {:buffer,
           {Pad.ref(:output, data.track_number),
            %Buffer{
              payload: data.data,
              dts: (state.current_timecode + data.timecode) * state.timestamp_scale
            }}}

        classify_buffer_action(buffer_action, state)

      _other_element ->
        state
    end
  end

  defp update_demands(state, context) do
    demands =
      context.pads
      |> Enum.filter(fn {id, _pad_data} -> id != :input end)
      |> Enum.map(fn {{Membrane.Pad, :output, id}, pad_data} -> {id, pad_data.demand} end)
      |> Enum.into(%{})

    blocked? = state.phase != :all_outputs_linked or Enum.any?(demands, fn {_k, v} -> v < 1 end)
    %State{state | demands: demands, blocked?: blocked?}
  end

  defp demand_if_not_blocked(state) do
    if not state.blocked? do
      actions = Qex.push(state.actions, {:demand, :input})
      %State{state | actions: actions}
    else
      state
    end
  end

  defp classify_buffer_action(
         {:buffer, {{Membrane.Pad, :output, id}, _buffer}} = buffer_action,
         state
       ) do
    if not state.blocked? and state.demands[id] > 0 do
      new_demands = Map.update!(state.demands, id, &(&1 - 1))
      %State{state | actions: Qex.push(state.actions, buffer_action), demands: new_demands}
    else
      %State{state | cache: Qex.push(state.cache, buffer_action), blocked?: true}
    end
  end

  defp reclassify_cached_buffer_actions(state) do
    Enum.reduce(state.cache, %State{state | cache: Qex.new()}, &classify_buffer_action/2)
  end

  defp send_actions(state) do
    {{:ok, Enum.into(state.actions, [])}, %State{state | actions: Qex.new()}}
  end

  defp notify_about_new_tracks(tracks) do
    tracks
    |> Enum.map(fn track -> {:notify, {:new_track, track}} end)
    |> Qex.new()
  end

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

  defp parse(bytes) do
    Membrane.WebM.Parser.Helper.parse(
      bytes,
      &Membrane.WebM.Schema.webm/1
    )
  end
end
