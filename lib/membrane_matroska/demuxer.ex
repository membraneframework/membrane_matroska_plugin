defmodule Membrane.Matroska.Demuxer do
  @moduledoc """
  Filter element for demuxing Matroska files.

  Receives a bytestream in Matroska file format as input and outputs the constituent tracks of that file
  onto seperate pads.

  This demuxer is only capable of demuxing tracks encoded with VP8, VP9, H264 or Opus.
  """

  # Works in three phases:

  # - :reading_header
  #   Demands and parses the beginning bytes of the Matroska file describing it's contents and sends:
  #   `{:notify_parent, {:new_track, {track_id, track_t}}}`
  #   notification to the parent pipeline for every track contained in the file.

  # - :awaiting_linking
  #   Pauses and waits for an output pad to be linked for every track in the file.
  #   Expects elements to be linked via pad `Pad.ref(:output, track_id)`.

  # - :all_outputs_linked
  #   Once all the expected output pads are linked it starts streaming the file's media with speed adjusted
  #   to the slowest of the output elements i.e. pausing when demands on that element's pad equals 0.

  use Membrane.Filter

  alias Membrane.{Buffer, H264, Matroska, Opus, RemoteStream, VP8, VP9}
  alias Membrane.Pipeline.Action

  def_input_pad :input,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers,
    accepted_format:
      %RemoteStream{content_format: format, type: :bytestream}
      when format in [nil, :WEBM, Matroska]

  def_output_pad :output,
    availability: :on_request,
    mode: :pull,
    accepted_format:
      any_of(
        %H264{stream_structure: {:avc3, _dcr}},
        Opus,
        %RemoteStream{content_format: format, type: :packetized} when format in [VP8, VP9]
      )

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
            codec: :vp8 | :vp9 | :h264,
            uid: non_neg_integer,
            active: boolean,
            height: non_neg_integer,
            width: non_neg_integer,
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
  def handle_init(_ctx, _options) do
    {[], %State{}}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[demand: :input], state}
  end

  @impl true
  def handle_end_of_stream(:input, context, state) do
    cached_buffers = Enum.to_list(state.cache)

    end_actions =
      context.pads
      |> Enum.filter(fn {_pad_ref, pad_data} -> pad_data.direction == :output end)
      |> Enum.map(fn {pad_ref, _pad_data} -> {:end_of_stream, pad_ref} end)

    {cached_buffers ++ end_actions, state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, id), _ctx, %State{tracks: tracks} = state) do
    track = tracks[id]

    caps =
      case track.codec do
        :opus ->
          %Opus{channels: track.channels, self_delimiting?: false}

        :vp8 ->
          # %VP8{width: track.width, height: track.height}
          %RemoteStream{content_format: VP8, type: :packetized}

        :vp9 ->
          # %VP9{width: track.width, height: track.height}
          %RemoteStream{content_format: VP9, type: :packetized}

        :h264 ->
          %H264{
            # Based on https://www.matroska.org/technical/codec_specs.html V_MPEG4/ISO/AVC section
            # it's always NALu
            alignment: :nalu,
            stream_structure: {:avc3, track.codec_private}
          }

        :vorbis ->
          raise "Track #{id} is encoded with Vorbis which is not supported by the demuxer"
      end

    state = %State{state | tracks: put_in(tracks[id].active, true)}

    state =
      if Enum.all?(state.tracks, fn {_k, v} -> v.active end),
        do: %State{state | phase: :all_outputs_linked},
        else: state

    {[stream_format: {Pad.ref(:output, id), caps}], state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: bytes}, context, state) do
    unparsed = state.parser_acc <> bytes

    {parsed, unparsed} = Matroska.Parser.Helper.parse(unparsed)

    state = %State{state | parser_acc: unparsed}

    {actions, state} = process_elements({Qex.new(), context, state}, parsed)

    # if not even a single element could be parsed then demand more data and try again
    if parsed == [] or state.phase == :reading_header do
      {[demand: :input], state}
    else
      demand_if_not_blocked({actions, state})
    end
  end

  @impl true
  def handle_demand(Pad.ref(:output, _id), _size, :buffers, context, state)
      when state.phase == :all_outputs_linked do
    # reconsider if cached buffers can now be sent
    {Qex.new(), state}
    |> reclassify_cached_buffer_actions(context)
    |> demand_if_not_blocked()
  end

  @impl true
  def handle_demand(Pad.ref(:output, _id), _size, :buffers, _ctx, state) do
    {[], state}
  end

  defp process_elements({actions, context, state}, elements_list) do
    {actions, _ctx, state} =
      Enum.reduce(Enum.reverse(elements_list), {actions, context, state}, &process_element/2)

    {actions, state}
  end

  defp process_element({element_name, data}, {actions, context, state}) do
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

      name when name in [:Block, :SimpleBlock] ->
        buffer_action =
          {:buffer,
           {Pad.ref(:output, data.track_number),
            %Buffer{
              payload: data.data,
              pts: (state.current_timecode + data.timecode) * state.timestamp_scale
            }}}

        classify_buffer_action(buffer_action, {actions, context, state})

      _other_element ->
        {actions, context, state}
    end
  end

  defp demand_if_not_blocked({actions, state}) do
    if blocked?(state) do
      {Enum.into(actions, []), state}
    else
      actions = Qex.push(actions, {:demand, :input})
      {Enum.into(actions, []), state}
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
    {actions, _ctx, state} =
      Enum.reduce(
        state.cache,
        {actions, context, %State{state | cache: Qex.new()}},
        &classify_buffer_action/2
      )

    {actions, state}
  end

  defp notify_about_new_tracks(tracks) do
    tracks
    |> Enum.map(fn track -> {:notify_parent, {:new_track, track}} end)
    |> Qex.new()
  end

  defp identify_tracks(tracks, timestamp_scale) do
    tracks = Keyword.get_values(tracks, :TrackEntry)

    for track <- tracks, into: %{} do
      codec_delay = track[:CodecDelay]
      codec_delay = if codec_delay == nil, do: 0, else: codec_delay

      info =
        case track[:TrackType] do
          :audio ->
            %{
              codec: track[:CodecID],
              uid: track[:TrackUID],
              active: false,
              channels: track[:Audio][:Channels],
              codec_delay: codec_delay
            }

          :video ->
            %{
              codec_private: track[:CodecPrivate],
              codec: track[:CodecID],
              codec_delay: codec_delay,
              uid: track[:TrackUID],
              active: false,
              height: track[:Video][:PixelHeight],
              width: track[:Video][:PixelWidth],
              scale: timestamp_scale
            }
        end

      {track[:TrackNumber], info}
    end
  end
end
