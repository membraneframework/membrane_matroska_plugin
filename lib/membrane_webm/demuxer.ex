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
    defstruct todo: nil, track_info: nil
  end

  @impl true
  def handle_init(_) do
    {:ok, %State{}}
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
  def handle_demand(Pad.ref(:output, id), _size, :buffers, _context, state) do
    caps =
      case state.track_info[id].codec do
        :opus ->
          %Opus{channels: state.track_info[id].channels, self_delimiting?: false}

        :vp8 ->
          %RemoteStream{
            content_format: VP8,
            type: :packetized
          }

        :vp9 ->
          %RemoteStream{
            content_format: VP9,
            type: :packetized
          }
      end

    {{:ok,
      [
        {:caps, {Pad.ref(:output, id), caps}},
        state.todo[id],
        {:end_of_stream, Pad.ref(:output, id)}
      ]}, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: {name, data} = parsed} = buf, _context, state) do
    IO.puts("      Demuxer received #{name}")
    {{:ok, demand: {:input, 1}}, state}

    # track_info = identify_tracks(parsed)
    # tracks = tracks(parsed)
    # actions = Enum.map(track_info, &notify_output/1)
    # sent = for track <- tracks, into: %{}, do: send(track)
    # newstate = %{state | todo: sent, track_info: track_info}
    # {{:ok, actions}, newstate}
  end

  defp send({track_num, track}) do
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
    tracks = children(parsed[:Segment][:Tracks], :TrackEntry)

    timecode_scale = timecode_scale(parsed)

    for track <- tracks, into: %{} do
      if track[:TrackType] == :audio do
        {
          track[:TrackNumber],
          %{
            codec: track[:CodecID],
            channels: track[:Audio][:Channels]
          }
        }
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
    clusters = children(parsed_webm[:Segment], :Cluster)
    cluster_timecodes = Enum.map(clusters, fn c -> c[:Timecode] end)

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

  def children(element_list, name) when is_list(element_list) do
    Keyword.get_values(element_list, name)
  end
end
