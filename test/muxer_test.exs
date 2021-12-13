defmodule Membrane.WebM.MuxerTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions
  alias Membrane.Testing
  alias Membrane.{Buffer, Opus}

  @fixtures_dir "./test/fixtures/"
  @output_dir "./test/results/"

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
        |> to(:muxer)
        |> to(:sink)
      ]

      {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
    end
  end

  test "mux single vp8" do
    test_stream("1_vp8.ivf", "muxed_vp8.webm")
  end

  test "mux single vp9" do
    test_stream("1_vp9.ivf", "muxed_vp9.webm")
  end

  test "mux opus from buffers" do
    test_from_buffers()
  end

  defp test_from_buffers() do
    buffers =
      (@fixtures_dir <> "buffers_dump.opus")
      |> File.read!()
      |> :erlang.binary_to_term()
      |> Enum.reverse()

    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: TestPipelineOpus,
        custom_args: %{
          output_file: @output_dir <> "muxed_opus.webm",
          buffers: buffers
        }
      }
      |> Testing.Pipeline.start_link()

    Testing.Pipeline.play(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :playing)

    assert_start_of_stream(pipeline, :sink)

    assert_end_of_stream(pipeline, :muxer, :input)

    # assert File.read!(@output_dir <> "muxed_opus.webm") ==
    #          File.read!(@fixtures_dir <> "muxed_opus.webm")

    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
  end

  defp test_stream(input_file, output_file) do
    if !File.exists?(@output_dir) do
      File.mkdir!(@output_dir)
    end

    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: TestPipelineVpx,
        custom_args: %{
          input_file: @fixtures_dir <> input_file,
          output_file: @output_dir <> output_file
        }
      }
      |> Testing.Pipeline.start_link()

    Testing.Pipeline.play(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :playing)

    assert_end_of_stream(pipeline, :sink, :timeout, 2_000)

    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
    assert_pipeline_playback_changed(pipeline, _, :stopped)

    # result_file: @output_dir <> output_file

    # for {reference, result} <- args do
    #   assert File.read!(@fixtures_dir <> reference) ==
    #            File.read!(@output_dir <> result)
    # end
  end
end
