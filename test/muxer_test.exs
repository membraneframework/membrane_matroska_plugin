# TODO: delete. this 'test' is for development and debugging, not testing

defmodule Membrane.WebM.MuxerTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.Testing

  alias Membrane.Opus

  @input_dir "./test/fixtures/"
  @output_dir "./test/results/"

  defmodule TestPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(options) do
      source =
        if options.from_dump? do
          %Testing.Source{
            output: Testing.Source.output_from_buffers(options.buffers),
            caps: %Opus{channels: 2, self_delimiting?: false}
          }
        else
          %Membrane.File.Source{
            location: options.input_file,
            chunk_size: 1_000_000_000
          }
        end

      children = [
        source: source,
        muxer: Membrane.WebM.Muxer,
        sink: %Membrane.File.Sink{
          location: options.output_dir <> "muxer_output.webm"
        }
      ]

      links = [
        link(:source)
        |> to(:muxer)
        |> to(:sink)
      ]

      {{:ok, spec: %ParentSpec{children: children, links: links}},
       %{output_dir: options.output_dir}}
    end
  end

  # test "mux" do
  #   test_stream("1_vp8.ivf", ["muxer_output.webm"], ["muxer_output.webm"])
  # end

  test "mux opus from buffers" do
    buffers =
      (@input_dir <> "buffers_dump.opus")
      |> File.read!()
      |> :erlang.binary_to_term()
      |> Enum.reverse()

    # IO.inspect(buffers)

    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: TestPipeline,
        custom_args: %{
          output_dir: @output_dir,
          from_dump?: true,
          # result_file: @results_dir <> @result_file,
          buffers: buffers
        }
      }
      |> Testing.Pipeline.start_link()

    Testing.Pipeline.play(pipeline)
    # assert_pipeline_playback_changed(pipeline, _, :playing)

    # assert_start_of_stream(pipeline, :sink)

    assert_end_of_stream(pipeline, :muxer, :input, 10_000)

    # assert File.read!(@results_dir <> @result_file) ==
    #          File.read!(@fixtures_dir <> @input_file)

    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
  end

  defp test_stream(input_file, references, results) do
    args = Enum.zip(references, results)

    if !File.exists?(@output_dir) do
      File.mkdir!(@output_dir)
    end

    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: TestPipeline,
        custom_args: %{
          input_file: @input_dir <> input_file,
          output_dir: @output_dir,
          from_dump?: false
        }
      }
      |> Testing.Pipeline.start_link()

    Testing.Pipeline.play(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :playing)

    assert_end_of_stream(pipeline, :sink)

    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
    assert_pipeline_playback_changed(pipeline, _, :stopped)

    # for {reference, result} <- args do
    #   assert File.read!(@input_dir <> reference) ==
    #            File.read!(@output_dir <> result)
    # end
  end
end
