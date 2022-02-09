defmodule Membrane.WebM.MuxerTest do
  # note that input pad ids should be set to a random value:
  # :random.uniform(1 <<< 64)
  # here numbers are hardcoded to achieve reproducibility

  use ExUnit.Case
  use Bitwise

  import Membrane.Testing.Assertions
  alias Membrane.Testing
  alias Membrane.{Buffer, Opus}

  @fixtures_dir "./test/fixtures/"

  defmodule TestPipelineOpus do
    use Membrane.Pipeline

    @impl true
    def handle_init(options) do
      source = %Testing.Source{
        output: Testing.Source.output_from_buffers(options.buffers),
        caps: %Opus{channels: 2, self_delimiting?: false}
      }

      children = [
        source: source,
        deserializer: Membrane.Element.IVF.Deserializer,
        muxer: Membrane.WebM.Muxer,
        sink: %Membrane.File.Sink{
          location: options.output_file
        }
      ]

      links = [
        link(:source)
        |> via_in(Pad.ref(:input, 17_447_232_417_024_423_937))
        |> to(:muxer)
        |> to(:sink)
      ]

      {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
    end
  end

  defmodule TestPipelineVpx do
    use Membrane.Pipeline

    @impl true
    def handle_init(options) do
      children = [
        source: %Membrane.File.Source{
          location: options.input_file
        },
        deserializer: Membrane.Element.IVF.Deserializer,
        muxer: Membrane.WebM.Muxer,
        sink: %Membrane.File.Sink{
          location: options.output_file
        }
      ]

      links = [
        link(:source)
        |> to(:deserializer)
        |> via_in(Pad.ref(:input, 13_337_737_628_113_408_001))
        |> to(:muxer)
        |> to(:sink)
      ]

      {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
    end
  end

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
    def handle_init(_options) do
      {:ok, %{cache: []}}
    end

    @impl true
    def handle_demand(:output, size, :buffers, _context, state) do
      {{:ok, demand: {:input, size}}, state}
    end

    @impl true
    def handle_end_of_stream(:input, _context, state) do
      IO.puts("Don't kill me - working. May take 10 seconds or so")
      output = inspect(state.cache, limit: :infinity, pretty: true)
      {{:ok, [buffer: {:output, %Buffer{payload: output}}, end_of_stream: :output]}, state}
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

  defmodule TestPipelineMany do
    use Membrane.Pipeline

    @impl true
    def handle_init(options) do
      opus_source = %Testing.Source{
        output: Testing.Source.output_from_buffers(options.buffers),
        caps: %Opus{channels: 2, self_delimiting?: false}
      }

      children = [
        vpx_source: %Membrane.File.Source{
          location: options.input_file
        },
        deserializer: Membrane.Element.IVF.Deserializer,
        opus_source: opus_source,
        muxer: Membrane.WebM.Muxer,
        sink: %Membrane.File.Sink{
          location: options.output_file
        },
        parser: Membrane.WebM.Parser,
        printer: Printer
      ]

      links = [
        link(:vpx_source)
        |> to(:deserializer)
        |> via_in(Pad.ref(:input, 11_020_961_587_148_742_657))
        |> to(:muxer),
        link(:opus_source)
        |> via_in(Pad.ref(:input, 16_890_875_709_512_990_721))
        |> to(:muxer),
        link(:muxer)
        # |> to(:parser)
        # |> to(:printer)
        |> to(:sink)
      ]

      {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
    end
  end

  defp test_from_buffers(tmp_dir) do
    buffers =
      (@fixtures_dir <> "buffers_dump.opus")
      |> File.read!()
      |> :erlang.binary_to_term()
      |> Enum.reverse()

    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: TestPipelineOpus,
        custom_args: %{
          output_file: tmp_dir <> "output.webm",
          buffers: buffers
        }
      }
      |> Testing.Pipeline.start_link()

    play_and_validate(pipeline, "muxed_opus.webm", tmp_dir)
  end

  defp test_stream(input_file, reference, tmp_dir) do
    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: TestPipelineVpx,
        custom_args: %{
          input_file: @fixtures_dir <> input_file,
          output_file: tmp_dir <> "output.webm"
        }
      }
      |> Testing.Pipeline.start_link()

    play_and_validate(pipeline, reference, tmp_dir)
  end

  defp test_many(tmp_dir) do
    buffers =
      (@fixtures_dir <> "buffers_dump.opus")
      |> File.read!()
      |> :erlang.binary_to_term()
      |> Enum.reverse()

    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: TestPipelineMany,
        custom_args: %{
          input_file: @fixtures_dir <> "1_vp8.ivf",
          output_file: tmp_dir <> "output.webm",
          buffers: buffers
        }
      }
      |> Testing.Pipeline.start_link()

    play_and_validate(pipeline, "combined.webm", tmp_dir)
  end

  defp play_and_validate(pipeline, output_file_name, tmp_dir) do
    Testing.Pipeline.play(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :playing)
    assert_start_of_stream(pipeline, :sink, :input, 100_000)
    assert_end_of_stream(pipeline, :sink, :input, 100_000)
    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
    assert_pipeline_playback_changed(pipeline, _, :stopped)
    assert File.read!(@fixtures_dir <> output_file_name) == File.read!(tmp_dir <> "output.webm")
  end

  @tag :tmp_dir
  test "mux single vp8", %{tmp_dir: tmp_dir} do
    test_stream("1_vp8.ivf", "muxed_vp8.webm", tmp_dir <> "/")
  end

  @tag :tmp_dir
  test "mux single vp9", %{tmp_dir: tmp_dir} do
    test_stream("1_vp9.ivf", "muxed_vp9.webm", tmp_dir <> "/")
  end

  @tag :tmp_dir
  test "mux opus from buffers", %{tmp_dir: tmp_dir} do
    test_from_buffers(tmp_dir <> "/")
  end

  @tag :tmp_dir
  test "mux two streams into one file, then parse it for debugging", %{tmp_dir: tmp_dir} do
    test_many(tmp_dir <> "/")
  end
end
