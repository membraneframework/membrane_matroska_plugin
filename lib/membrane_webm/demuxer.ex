defmodule Membrane.WebM.Demuxer do
  use Membrane.Filter

  alias Membrane.{Buffer, Time, RemoteStream}
  alias Membrane.{VP8, VP9}

  def_input_pad :input,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers,
    caps: :any

  # def_output_pad :output,
  # availability: :always,
  # mode: :pull,
  # caps: {RemoteStream, content_format: VP9, type: :packetized}

  def_output_pad :output,
    availability: :always,
    mode: :pull,
    caps: :any

  def_options output_as_string: [
                spec: boolean,
                default: false,
                description: "Output tracks as pretty-formatted string for inspection."
              ]

  @impl true
  def handle_init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    caps = %RemoteStream{content_format: VP8, type: :packetized}
    {{:ok, caps: {:output, caps}}, state}
  end

  # @impl true
  # def handle_prepared_to_playing(_ctx, state) do
  #   caps = %Membrane.Opus{channels: 2, self_delimiting?: false}
  #   {{:ok, caps: {:output, caps}}, state}
  # end

  @impl true
  def handle_demand(:output, size, :buffers, _context, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(:input, buffer, _context, state) do
    parsed = buffer.payload
    IO.inspect(track_info = identify_tracks(parsed))
    tracks = tracks(parsed)

    out = tracks
    # provide width, height, rate and scale
    out = inspect(out, limit: :infinity, pretty: true)
    out = %Buffer{payload: out}
    {{:ok, buffer: {:output, out}}, state}
  end

  defp timecode_scale(parsed_webm) do
    # scale of block timecodes in nanoseconds
    # should be 1_000_000 i.e. 1 ms
    parsed_webm
    |> child(:Segment)
    |> child(:Info)
    |> child(:TimecodeScale)
    |> unpack
  end

  def identify_tracks(parsed) do
    tracks =
      parsed
      |> child(:Segment)
      |> child(:Tracks)
      |> children(:TrackEntry)
      |> unpack

    timecode_scale = timecode_scale(parsed)

    for track <- tracks, into: %{} do
      if track[:TrackType].data == :audio do
        {track[:TrackNumber].data, %{codec: track[:CodecID].data}}
      else
        {
          track[:TrackNumber].data,
          %{
            codec: track[:CodecID].data,
            height: track[:Video].data[:PixelHeight].data,
            width: track[:Video].data[:PixelWidth].data,
            rate: Time.second(),
            scale: timecode_scale
          }
        }
      end
    end
  end

  def get_data(element_list, keys) when is_list(element_list) do
    Enum.map(element_list, &get_data(&1, keys))
  end

  def get_data(element, keys) do
    for key <- keys, key in children(element), into: %{}, do: {key, unpack(child(element, key))}
  end

  def hexdump(bytes) do
    bytes
    |> Base.encode16()
    |> String.codepoints()
    |> Enum.chunk_every(4)
    |> Enum.intersperse(" ")
    |> Enum.chunk_every(8 * 2)
    |> Enum.intersperse("\n")
    |> IO.puts()
  end

  def tracks(parsed_webm) do
    clusters =
      parsed_webm[:Segment]
      |> children(:Cluster)

    cluster_timecodes =
      clusters
      |> children(:Timecode)
      |> unpack

    augmented_blocks =
      for {cluster, timecode} <- Enum.zip(clusters, cluster_timecodes) do
        blocks =
          cluster
          |> children(:SimpleBlock)
          |> unpack()
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
    %Buffer{payload: data, metadata: %{timestamp: timecode}}
  end

  def unpack(elements) when is_list(elements) do
    Enum.map(elements, &unpack(&1))
  end

  def unpack(element) do
    element.data
  end

  def child(element_list, name) when is_list(element_list) do
    # assumes there's only one child - this should be checked!
    element_list[name]
  end

  def child(element, name) do
    # assumes there's only one child - this should be checked!
    element.data[name]
  end

  def children(element_list, name) when is_list(element_list) do
    element_list
    |> Enum.flat_map(&children(&1, name))
  end

  def children(element, name) do
    Keyword.get_values(element.data, name)
  end

  def children(element) do
    if element.type == :master do
      for {key, _data} <- element.data, do: key
    else
      nil
    end
  end
end
