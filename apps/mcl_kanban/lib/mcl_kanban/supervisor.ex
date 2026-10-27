defmodule MclKanban.Supervisor do
  # One child, and it is the crew department's own: the reconcile that keeps a
  # dropped crew from keeping the board (#40). Everything else supervises
  # itself: evoq starts aggregates on demand, and macula spawns a responder per
  # call.
  @moduledoc false

  use Supervisor

  def start_link, do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init([]) do
    children = [GuideCardLifecycle.CrewFacts.CrewStandingReconciler]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
