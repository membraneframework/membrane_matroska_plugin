defmodule Membrane.WebM.Demuxer do
  use Membrane.Filter

  alias Membrane.{Buffer, Time, RemoteStream}
  alias Membrane.{VP8, VP9}

  def_input_pad :input,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers,
    caps: :any

  def_output_pad :output,
    availability: :on_request,
    mode: :pull,
    caps: :any

<<<<<<< HEAD
  defmodule State do
    defstruct todo: nil, track_info: nil
  end

  @impl true
  def handle_init(_) do
    {:ok, %State{}}
=======
  def_options output_as_string: [
                spec: boolean,
                default: false,
                description: "Outputs tracks as pretty-formatted string for inspection."
              ]

  @impl true
  def handle_init(_) do
    state = %{tracks: []}

     {:ok, state}
>>>>>>> parent of e13d6a2 (pass ivf option through demuxer track details)
  end

  @impl true
  def handle_prepared_to_playing(_context, _state) do
    {{:ok, demand: :input}, %{todo: nil, track_info: nil}}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _context, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_demand(Pad.ref(:output, id), _size, :buffers, _context, state) do
    case state.track_info[id].codec do
      :opus ->
<<<<<<< HEAD
        # TODO other channel counts
=======
>>>>>>> parent of e13d6a2 (pass ivf option through demuxer track details)
        caps = %Membrane.Opus{channels: 2, self_delimiting?: false}

        {{:ok,
          [
            {:caps, {Pad.ref(:output, id), caps}},
            state.todo[id],
            {:end_of_stream, Pad.ref(:output, id)}
          ]}, state}

      :vp8 ->
        caps = %RemoteStream{content_format: VP8, type: :packetized}

        {{:ok,
          [
            {:caps, {Pad.ref(:output, id), caps}},
            state.todo[id],
            {:end_of_stream, Pad.ref(:output, id)}
          ]}, state}

      :vp9 ->
        caps = %RemoteStream{content_format: VP9, type: :packetized}

        {{:ok,
          [
            {:caps, {Pad.ref(:output, id), caps}},
            state.todo[id],
            {:end_of_stream, Pad.ref(:output, id)}
          ]}, state}
    end
  end

  @impl true
  def handle_process(:input, buffer, _context, state) do
    parsed = buffer.payload
    track_info = identify_tracks(parsed)
    tracks = tracks(parsed)

    actions =
      track_info
      |> Enum.map(&notify_output/1)

    sent = for track <- tracks, into: %{}, do: send(track)
    newstate = %{state | todo: sent, track_info: track_info}
    {{:ok, actions}, newstate}
  end

  defp send({track_num, track}) do
    # track = %Buffer{payload: inspect(track, limit: :infinity, pretty: true)}
    {track_num, {:buffer, {Pad.ref(:output, track_num), track}}}
  end

  defp notify_output({track_id, details}) do
    {:notify, {:new_channel, {track_id, details}}}
  end

  defp timecode_scale(parsed_webm) do
    # scale of block timecodes in nanoseconds
    # should be 1_000_000 i.e. 1 ms
    parsed_webm[:Segment][:Info][:TimecodeScale]
  end

  def identify_tracks(parsed) do
    tracks =
      parsed[:Segment][:Tracks]
      |> children(:TrackEntry)

    timecode_scale = timecode_scale(parsed)

    for track <- tracks, into: %{} do
      if track[:TrackType] == :audio do
        {track[:TrackNumber], %{codec: track[:CodecID]}}
      else
        {
          track[:TrackNumber],
          %{
            codec: track[:CodecID],
            height: track[:Video][:PixelHeight],
            width: track[:Video][:PixelWidth],
            rate: Time.second(),
            scale: timecode_scale
          }
        }
      end
    end
  end

  def tracks(parsed_webm) do
    clusters =
      parsed_webm[:Segment]
      |> children(:Cluster)

    cluster_timecodes = child_foreach(clusters, :Timecode)

    augmented_blocks =
      for {cluster, timecode} <- Enum.zip(clusters, cluster_timecodes) do
        blocks =
          cluster
          |> children(:SimpleBlock)
          |> Enum.map(fn block ->
            %{
              timecode: timecode + block.timecode,
              track_number: block.track_number,
              data: block.data
            }
          end)

        blocks
      end

    augmented_blocks
    |> List.flatten()
    |> Enum.reverse()
    |> Enum.group_by(& &1.track_number, &packetize/1)
  end

  def packetize(%{timecode: timecode, data: data, track_number: _track_number}) do
    %Buffer{payload: data, metadata: %{timestamp: timecode * 1_000_000}}
  end

  def child(element_list, name) when is_list(element_list) do
    element_list[name]
  end

  def child_foreach(element_list, name) do
    Enum.map(element_list, &child(&1, name))
  end

  def children(element_list, name) when is_list(element_list) do
    Keyword.get_values(element_list, name)
  end
end
