defmodule GuideCardLifecycle.AdoptGoal.GoalAdoptedV1 do
  # Event: goal_adopted_v1.
  @moduledoc false

  alias GuideCardLifecycle.Actor

  def event_type, do: "goal_adopted_v1"

  def new(cmd) do
    Map.merge(Actor.record(cmd.by), %{
      event_type: event_type(),
      goal: cmd.goal,
      packages: cmd.packages,
      at: System.system_time(:millisecond)
    })
  end
end
