defmodule GuideCardLifecycle.DischargeAgent.MaybeDischargeAgent do
  # Handler: the owner, or the operator of the crew the agent belongs to
  # (#28). The supervisor itself cannot be discharged (the crew always has
  # one); a discharged operator leaves its crew without one. The prioritiser
  # is appointed by the owner once for all crews, so only the owner
  # discharges it, even when it is enlisted in an operator's crew (#29): an
  # operator does not undo the owner's appointment.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewState
  alias GuideCardLifecycle.DischargeAgent.{AgentDischargedV1, DischargeAgentV1}

  def handle_payload(state, payload), do: handle(state, struct(DischargeAgentV1, payload))

  def handle(%CrewState{} = crew, %DischargeAgentV1{} = cmd) do
    node_id = CrewState.node_id_of(crew, cmd.name)

    cond do
      # An unknown name is refused as such whoever asks: there is no crew to
      # command, so commands_crew?/2 would be handed a nil.
      node_id == nil ->
        {:error, :unknown_agent}

      not Actor.commands_crew?(cmd.by, CrewState.crew_of(crew, node_id)) ->
        {:error, :not_permitted}

      node_id == crew.supervisor ->
        {:error, :supervisor_required}

      node_id == crew.prioritiser and not Actor.allowed?(cmd.by, [:owner]) ->
        {:error, :appointed_by_owner}

      true ->
        {:ok, [AgentDischargedV1.new(cmd.by, node_id, CrewState.name_of(crew, node_id))]}
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
