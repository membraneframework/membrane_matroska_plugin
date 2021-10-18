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
    tracks_info = identify_tracks(parsed_webm)

    tracks =
      parsed_webm
      |> demux(tracks_info)

    {{:ok, buffer: {:output, tracks}}, state}
  end

  def identify_tracks(parsed_webm) do
    [%{TrackUID: 1, TrackCodec: :opus}]
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

  def demux(parsed_webm, tracks_info) do
    tracks = []
    for track_info <- tracks_info do
      %{TrackUID: track_UID, TrackCodec: track_codec} = track_info
      # TODO add filtering
      track =
        parsed_webm
        |> child(:Segment)
        |> children(:Cluster)
        |> children(:SimpleBlock)
        |> Enum.reverse()
        |> unpack()
        |> unpack()
        |> Enum.map(&(%Buffer{payload: &1}))

      tracks = [tracks | track]
    end
  end

  def demux_single_opus_track(parsed_file) do
    parsed_file
    |> child(:Segment)
    |> children(:Cluster)
    |> children(:SimpleBlock)
    |> Enum.reverse()
    |> unpack()
    |> unpack()
    |> Enum.map(&(%Buffer{payload: &1}))
  end

  def unpack(elements) when is_list(elements) do
    Enum.map(elements, &(unpack(&1)))
  end

  def unpack(element) do
    element.data
  end

  def child(elements_list, name) do
    # assumes there's only one child - this should be checked!
    Enum.find(elements_list, nil, &(&1[:name] == name))
  end

  def children(elements_list, name) when is_list(elements_list) do
    elements_list
    |> Enum.flat_map(&(children(&1, name)))
  end

  def children(element, name) do
    # assumes there's only one child - this should be checked!
    Enum.filter(element.data, &(&1[:name] == name))
  end
end
