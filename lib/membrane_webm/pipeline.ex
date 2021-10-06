defmodule Membrane.WebM.Pipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_) do
    children = [
      file_src: %Membrane.File.Source{location: Path.join([File.cwd!, "_stuff", "sample.webm"]), chunk_size: 1024},
      demuxer: Membrane.WebM.Demuxer,
      file_sink: %Membrane.File.Sink{location: Path.join([File.cwd!, "_stuff", "sink.webm"])}
    ]
    links = [
      link(:file_src)
      |> to(:demuxer)
      |> to(:file_sink)
    ]
    {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
  end

  # @impl true
  # def handle_notification(notification, source, _context, state) do
  #   # Membrane.Pipeline.stop_and_terminate(self())
  #   IO.puts(notification)
  #   IO.puts(source)
  #   {:ok, state}
  # end
end

# #! test
# Membrane.WebM.Pipeline.start_link()
# |> elem(1)
# |> tap(&Membrane.Pipeline.play/1)
# |> then(&Process.monitor/1)
