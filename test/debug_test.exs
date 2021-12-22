# TO BE REMOVED - FOR DEBUGGING ONLY
defmodule Membrane.WebM.PrettyPrint do
  use ExUnit.Case

  import Membrane.Testing.Assertions
  alias Membrane.Testing
  alias Membrane.Buffer

  defmodule Printer do
    use Membrane.Filter

    def_input_pad :input,
      availability: :always,
      mode: :pull,
      demand_unit: :buffers,
      caps: :any

    def_output_pad :output,
      availability: :always,
      mode: :pull,
      caps: :any

    @impl true
    def handle_init(_) do
      {:ok, %{cache: []}}
    end

    @impl true
    def handle_demand(:output, size, :buffers, _context, state) do
      {{:ok, demand: {:input, size}}, state}
    end

    @impl true
    def handle_end_of_stream(:input, _ctx, state) do
      IO.puts("Don't kill me - working. May take 10 seconds or so")
      output = inspect(state.cache, limit: :infinity, pretty: true)
      {{:ok, buffer: {:output, %Buffer{payload: output}}}, state}
    end

    @impl true
    def handle_process(
          :input,
          %Buffer{payload: data, metadata: %{webm: %{element_name: element_name}}},
          _context,
          state
        ) do
      {{:ok, demand: {:input, 1}}, %{state | cache: [{element_name, data} | state.cache]}}
    end
  end

  defmodule PrettyPrintPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(options) do
      children = [
        source: %Membrane.File.Source{
          location: options.input,
          chunk_size: 1_000_000
        },
        parser: Membrane.WebM.Parser,
        printer: Printer,
        sink: %Membrane.File.Sink{
          location: options.output
        }
      ]

      links = [
        link(:source)
        |> to(:parser)
        |> to(:printer)
        |> to(:sink)
      ]

      {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
    end
  end

  test "parse and pretty print a webm file" do
    run("test/results/muxed_opus.webm", "test/results/demuxed_opus.webp")
  end

  defp run(input, output) do
    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: PrettyPrintPipeline,
        custom_args: %{
          input: input,
          output: output
        }
      }
      |> Testing.Pipeline.start_link()

    Testing.Pipeline.play(pipeline)

    # needs to be a long timeout to write everything to file
    assert_end_of_stream(pipeline, :printer, :input, 100_000)

    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
  end
end
