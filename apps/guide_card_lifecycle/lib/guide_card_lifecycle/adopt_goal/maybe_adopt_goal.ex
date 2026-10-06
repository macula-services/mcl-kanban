defmodule GuideCardLifecycle.AdoptGoal.MaybeAdoptGoal do
  # Handler: the supervisor or the owner adopts the crew's goal (#18). Raf
  # sets it from the owner UI, the supervisor over the mesh (the crew mod's
  # /crew-goal). claim_next_card serves its packages first.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CrewAggregate, CrewState}
  alias GuideCardLifecycle.AdoptGoal.{AdoptGoalV1, GoalAdoptedV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(AdoptGoalV1, payload))

  def handle(%CrewState{}, %AdoptGoalV1{} = cmd),
    do: adopted(Actor.allowed?(cmd.by, @who), cmd)

  defp adopted(true, cmd), do: {:ok, [GoalAdoptedV1.new(cmd)]}
  defp adopted(false, _cmd), do: {:error, :not_permitted}

  def dispatch(%AdoptGoalV1{} = cmd) do
    :evoq_command.new(
      :adopt_goal,
      CrewAggregate,
      CrewAggregate.stream_id(),
      AdoptGoalV1.to_map(cmd)
    )
    |> :evoq_router.dispatch()
  end
end
