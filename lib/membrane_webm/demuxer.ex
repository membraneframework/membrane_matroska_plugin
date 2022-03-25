defmodule Membrane.WebM.Demuxer do
  @moduledoc """
  Filter element for demuxing WebM files.

  Receives a bytestream in WebM file format as input and outputs the constituent tracks of that file
  onto seperate pads.

  This demuxer is only capable of demuxing tracks encoded with VP8, VP9 or Opus.
  """

  # Works in three phases:

  # - :reading_header
  #   Demands and parses the beginning bytes of the WebM file describing it's contents and sends:
  #   `{:notify, {:new_track, {track_id, track_t}}}`
  #   notification to the parent pipeline for every track contained in the file.

  # - :awaiting_linking
  #   Pauses and waits for an output pad to be linked for every track in the file.
  #   Expects elements to be linked via pad `Pad.ref(:output, track_id)`.

  # - :all_outputs_linked
  #   Once all the expected output pads are linked it starts streaming the file's media with speed adjusted
  #   to the slowest of the output elements i.e. pausing when demands on that element's pad equals 0.

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
            cache: Qex.t(Action.t()),
            phase: :reading_header | :awaiting_linking | :all_outputs_linked,
            tracks: %{(pad_id :: non_neg_integer) => track_t},
            parser_acc: binary,
            current_timecode: integer
          }

    defstruct timestamp_scale: nil,
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
  def handle_end_of_stream(:input, context, state) do
    actions =
      context.pads
      |> Enum.filter(fn {_pad_ref, pad_data} -> pad_data.direction == :output end)
      |> Enum.map(fn {pad_ref, _pad_data} -> {:end_of_stream, pad_ref} end)

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

        :vorbis ->
          raise "Track #{id} is encoded with Vorbis which is not supported by the demuxer"
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

    {actions, state} =
      process_elements({Qex.new(), context, %State{state | parser_acc: unparsed}}, parsed)

    # if even one element couldn't be parsed then demand more data and try again
    if parsed == [] or state.phase == :reading_header do
      {{:ok, demand: :input}, state}
    else
      demand_if_not_blocked({actions, state})
    end
  end

  @impl true
  def handle_demand(Pad.ref(:output, _id), _size, :buffers, context, state) do
    if state.phase == :all_outputs_linked and blocked?(state) do
      # reconsider if cached buffers can now be sent
      {Qex.new(), state}
      |> reclassify_cached_buffer_actions(context)
      |> demand_if_not_blocked()
    else
      {:ok, state}
    end
  end

  defp process_elements({actions, context, state}, elements_list) do
    {actions, _context, state} =
      Enum.reduce(Enum.reverse(elements_list), {actions, context, state}, &process_element/2)

    {actions, state}
  end

  defp process_element({element_name, data} = _element, {actions, context, state}) do
    case element_name do
      :Info ->
        # scale of block timecodes in nanoseconds
        # should be 1_000_000 i.e. 1 ms
        {actions, context, %State{state | timestamp_scale: data[:TimestampScale]}}

      :Tracks ->
        tracks = identify_tracks(data, state.timestamp_scale)
        new_actions = notify_about_new_tracks(tracks)

        {Qex.join(new_actions, actions), context,
         %State{
           state
           | tracks: tracks,
             phase: :awaiting_linking
         }}

      :Timecode ->
        {actions, context, %State{state | current_timecode: data}}

      :SimpleBlock ->
        buffer_action =
          {:buffer,
           {Pad.ref(:output, data.track_number),
            %Buffer{
              payload: data.data,
              dts: (state.current_timecode + data.timecode) * state.timestamp_scale
            }}}

        classify_buffer_action(buffer_action, {actions, context, state})

      _other_element ->
        {actions, context, state}
    end
  end

  defp demand_if_not_blocked({actions, state}) do
    if not blocked?(state) do
      actions = Qex.push(actions, {:demand, :input})
      {{:ok, Enum.into(actions, [])}, state}
    else
      {{:ok, Enum.into(actions, [])}, state}
    end
  end

  # The demuxer demands input as fast as the slowest of it's output pads allows (i.e. demand > 0).
  defp classify_buffer_action(
         {:buffer, {Pad.ref(:output, id), _buffer}} = buffer_action,
         {actions, context, state}
       ) do
    if not blocked?(state) and context.pads[Pad.ref(:output, id)].demand > 0 do
      context = update_in(context.pads[Pad.ref(:output, id)].demand, &(&1 - 1))
      {Qex.push(actions, buffer_action), context, state}
    else
      {actions, context, %State{state | cache: Qex.push(state.cache, buffer_action)}}
    end
  end

  defp blocked?(state) do
    not Enum.empty?(state.cache) or state.phase != :all_outputs_linked
  end

  defp reclassify_cached_buffer_actions({actions, state}, context) do
    {actions, _context, state} =
      Enum.reduce(
        state.cache,
        {actions, context, %State{state | cache: Qex.new()}},
        &classify_buffer_action/2
      )

    {actions, state}
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
      &Membrane.WebM.Schema.deserialize_webm/1
    )
  end
end
