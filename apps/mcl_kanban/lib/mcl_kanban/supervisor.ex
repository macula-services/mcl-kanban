defmodule MclKanban.Supervisor do
  # NO CHILDREN. Each department supervises its own processes, evoq starts
  # aggregates on demand, and macula spawns a responder per call.
  @moduledoc false

  use Supervisor

  def start_link, do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init([]), do: Supervisor.init([], strategy: :one_for_one)
end
