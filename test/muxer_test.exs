# TODO: delete. this 'test' is for development and debugging, not testing

defmodule Membrane.WebM.MuxerTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.Testing

  @input_dir "./test/fixtures/"
  @output_dir "./test/debug/"

  defmodule TestPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(options) do
      children = [
        source: %Membrane.File.Source{
          location: options.input_file,
          chunk_size: 4096
        },
        muxer: %Membrane.WebM.Muxer{},
        sink: %Membrane.File.Sink{
          location: "test/debug/muxer_output.webm"
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

  test "mux" do
    test_stream("1_vp8.ivf", ["muxer_output.webm"], ["muxer_output.webm"])
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
          output_dir: @output_dir
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
