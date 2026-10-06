defmodule GuideCardLifecycle.DischargeAgent.MaybeDischargeAgent do
  # Handler: the supervisor or the owner discharges. The supervisor itself
  # cannot be discharged (the crew always has one); a discharged prioritiser
  # leaves the crew without one.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewState
  alias GuideCardLifecycle.DischargeAgent.{AgentDischargedV1, DischargeAgentV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(DischargeAgentV1, payload))

  def handle(%CrewState{} = crew, %DischargeAgentV1{} = cmd) do
    node_id = CrewState.node_id_of(crew, cmd.name)

    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      node_id == nil -> {:error, :unknown_agent}
      node_id == crew.supervisor -> {:error, :supervisor_required}
      true -> {:ok, [AgentDischargedV1.new(cmd.by, node_id, CrewState.name_of(crew, node_id))]}
    end
  end

  def dispatch(%DischargeAgentV1{} = cmd) do
    :evoq_command.new(
      :discharge_agent,
      CrewAggregate,
      CrewAggregate.stream_id(),
      DischargeAgentV1.to_map(cmd)
    )
    |> :evoq_router.dispatch()
  end
end
