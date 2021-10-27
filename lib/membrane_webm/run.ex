defmodule Run do
  # @on_load :run
  def run do
    {:ok, pid} = Membrane.WebM.Pipeline.start_link()
    Membrane.WebM.Pipeline.play(pid)
  end
end
