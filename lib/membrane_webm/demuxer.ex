defmodule Membrane.WebM.Demuxer do
  use Membrane.Filter

  alias Membrane.Buffer

  def_input_pad :input,
  availability: :always,
  mode: :pull,
  demand_unit: :buffers,
  caps: :any

  def_output_pad :output,
  availability: :always,
  mode: :pull,
  caps: {Membrane.Opus, channels: 2}

  @impl true
  def handle_init(_) do
    state = %{counter: 0, parsed: ""}
    {:ok, state}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    {{:ok, caps: {:output, %Membrane.Opus{channels: 2, self_delimiting?: false}}}, state}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _context, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(:input, buffer, _context, state) do
    parsed_webm = buffer.payload
    track_info = identify_tracks(parsed_webm)
    tracks = tracks(parsed_webm, track_info)
    demuxed = for track <- tracks do
      demux(track)
    end

    # {{:ok, buffer: {:output, demuxed[:opus]}}, state}
    # demuxed = List.first(demuxed)
    out = demuxed[:opus]
    # out = inspect(out, limit: :infinity, pretty: true)
    # out = %Buffer{payload: out}
    {{:ok, buffer: {:output, out}}, state}
  end

  def demux({codec, data}) do
    data =
      data
      # |> Enum.reverse()
      |> Enum.map(fn x -> %Buffer{payload: x} end)

    {codec, data}
  end

  def identify_tracks(parsed_webm) do
    tracks =
      parsed_webm
      |> child(:Segment)
      |> child(:Tracks)
      |> children(:TrackEntry)
      |> get_values([:TrackNumber, :CodecID])

    for track <- tracks, into: %{}, do: {track[:TrackNumber], track[:CodecID]}
  end

  def get_values(element_list, keys) when is_list element_list do
    Enum.map(element_list, &get_values(&1, keys))
  end

  def get_values(element, keys) do
    for key <- keys, into: %{}, do: {key, unpack(child(element, key))}
  end

  def hexdump(bytes) do
    bytes
    |> Base.encode16
    |> String.codepoints()
    |> Enum.chunk_every(4)
    |> Enum.intersperse(" ")
    |> Enum.chunk_every(8*2)
    |> Enum.intersperse("\n")
    |> IO.puts()
  end

  def tracks(parsed_webm, track_info) do
    parsed_webm
    |> child(:Segment)
    |> children(:Cluster)
    |> children(:SimpleBlock)
    |> Enum.reverse()
    |> unpack()
    |> Enum.group_by(&(track_info[&1.track_number]), &unpack/1)
  end

  def demux_single_opus_track(parsed_file) do
    parsed_file
    |> child(:Segment)
    |> children(:Cluster)
    # |> adjust_timecodes()
    |> children(:SimpleBlock)
    |> Enum.reverse()
    |> unpack()
    |> unpack()
    |> Enum.map(&(%Buffer{payload: &1}))
  end

  # def adjust_timecodes(clusters) do
  #   for cluster <- clusters do
  #     cluster_time = child(cluster, :TimeCode) |> unpack()
  #     for block in
  #   end
  # end

  def unpack(elements) when is_list(elements) do
    Enum.map(elements, &(unpack(&1)))
  end

  def unpack(element) do
    element.data
  end

  def child(element_list, name) when is_list(element_list) do
    # assumes there's only one child - this should be checked!
    Enum.find(element_list, nil, &(&1[:name] == name))
  end

  def child(element, name) do
    # assumes there's only one child - this should be checked!
    Enum.find(element.data, nil, &(&1[:name] == name))
  end

  def children(element_list, name) when is_list(element_list) do
    element_list
    |> Enum.flat_map(&(children(&1, name)))
  end

  def children(element, name) do
    Enum.filter(element.data, &(&1[:name] == name))
  end

#   def get_fields(element_list, names) when is_list(element_list) do
#     element_list
#     |> Enum.map()
#     |> _get_fields(names)
#   end

#   def _get_fields(element, names) do
#     result = %{}
#     for name <- names do
#       result = Map.put(result, name, child(element, name))
#     end
#     result
#   end

end
