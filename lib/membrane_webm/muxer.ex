defmodule Membrane.WebM.Muxer do
  @moduledoc """
  Module for muxing WebM files.

  """
  use Membrane.Filter

  alias Membrane.{Buffer, RemoteStream, Time}
  alias Membrane.{Opus, VP8, VP9}
  alias Membrane.WebM.Schema
  alias Membrane.WebM.Serializer

  def_input_pad :input,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers,
    caps: :any

  def_output_pad :output,
    availability: :on_request,
    mode: :pull,
    caps: :any

  # nanoseconds in a milisecond # TODO: is this right?
  @time_base 1_000_000

  @ebml_header {
    :EBML,[
      DocTypeReadVersion: 2,
      DocTypeVersion: 4,
      DocType: "webm",
      EBMLMaxSizeLength: 8,
      EBMLMaxIDLength: 4,
      EBMLReadVersion: 1,
      EBMLVersion: 1
    ]
  }

  defmodule State do
    defstruct timecodescale: nil, cache: [], tracks: %{}
  end

  @impl true
  def handle_init(_) do
    {{:ok, buffer: {:output, %Buffer{payload: construct_EBML_header()}}}, %State{}}
  end

  @impl true
  def handle_prepared_to_playing(_context, state) do
    {{:ok, demand: :input}, state}
  end

  # FIXME: ignoring for now
  @impl true
  def handle_demand(Pad.ref(:output, _id), _size, :buffers, _context, state) do
    {:ok, state}
  end

  @impl true
  def handle_caps(:input, _context, state) do
    {:ok, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: _data}, _context, state) do
    IO.puts("        Muxer got buffer")

    {:ok, state}
  end

  defp construct_EBML_header() do
    Serializer.serialize(@ebml_header)
  end
end
