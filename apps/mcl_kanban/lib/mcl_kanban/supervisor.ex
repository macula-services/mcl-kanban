defmodule MclKanban.Supervisor do
  # The crew department's own two children (#40): the gate every crew fact is
  # believed through, and the reconcile that keeps a dropped crew from keeping
  # the board. The gate is first, because the reconcile asks it. Everything
  # else supervises itself: evoq starts aggregates on demand, and macula
  # spawns a responder per call.
  @moduledoc false

  use Supervisor

  alias GuideCardLifecycle.CrewFacts.{CrewFactGate, CrewStandingReconciler}

  def start_link, do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init([]) do
    children = [CrewFactGate, CrewStandingReconciler]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
