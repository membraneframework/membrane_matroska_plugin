Mix.install([
  :membrane_core,
  {:membrane_matroska_plugin, path: __DIR__ |> Path.join("..") |> Path.expand()},
  :membrane_hackney_plugin,
  :membrane_h264_ffmpeg_plugin,
  :membrane_mp4_plugin,
  :membrane_opus_plugin,
  {:membrane_ogg_plugin, github: "membraneframework/membrane_ogg_plugin"}
])

defmodule Example do
  use Membrane.Pipeline

  @samples_url "https://raw.githubusercontent.com/membraneframework/static/gh-pages/samples/big-buck-bunny/"
  @input_url @samples_url <> "bun33s.mkv"
  @output_file Path.expand("big_buck_bunny33s.mkv")
  @output_dir "./demuxing_output/"

  @impl true
  def handle_init(options) do

    File.mkdir(@output_dir)

    children = [
      source: %Membrane.Hackney.Source{
        location: @input_url,
        hackney_opts: [follow_redirect: true]
      },
      demuxer: Membrane.Matroska.Demuxer
    ]

    links = [
      link(:source)
      |> to(:demuxer)
    ]


    {{:ok, spec: %ParentSpec{children: children, links: links}, playback: :playing}, %{tracks: 2}}
  end

  @impl true
  def handle_notification({:new_track, {track_id, track_info}}, :demuxer, _context, state) do

      cond do
        track_info.codec == :opus ->
          children = %{
            {:payloader, track_id} => %Membrane.Ogg.Payloader.Opus{
              frame_size: 20
            },
            {:sink, track_id} => %Membrane.File.Sink{
              location: Path.join(@output_dir, "#{track_id}.ogg")
            }
          }

          links = [
            link(:demuxer)
            |> via_out(Pad.ref(:output, track_id))
            |> to({:payloader, track_id})
            |> to({:sink, track_id})
          ]

          {{:ok, spec: %ParentSpec{children: children, links: links}}, state}

        track_info.codec == :h264 ->
          children = %{
            :parser => %Membrane.H264.FFmpeg.Parser{
              skip_until_parameters?: false,
              attach_nalus?: true
            },
            {:sink, track_id} => %Membrane.File.Sink{
              location: Path.join(@output_dir, "#{track_id}.h264")
            }
          }

          links = [
            link(:demuxer)
            |> via_out(Pad.ref(:output, track_id))
            |> to(:parser)
            |> to({:sink, track_id})
          ]

          {{:ok, spec: %ParentSpec{children: children, links: links}}, state}

        true ->
          raise "Unsupported codec #{track_info.codec}"
    end
  end

  # Next three functions are only a logic for terminating a pipeline when it's done, you don't need to worry
  @impl true
  def handle_element_end_of_stream({{:sink, _},:input}, _ctx, state) when state.tracks == 1 do
    Membrane.Pipeline.terminate(self())
    {:ok, state}
  end

  @impl true
  def handle_element_end_of_stream({{:sink, _},:input}, _ctx, state) do
    {:ok, %{tracks: state.tracks - 1}}
  end

  def handle_element_end_of_stream(element, _ctx, state) do
    {:ok, state}
  end
end

{:ok, pipeline} = Example.start_link()
monitor_ref = Process.monitor(pipeline)

receive do
  {:DOWN, ^monitor_ref, :process, _pid, _reason} -> :ok
end
