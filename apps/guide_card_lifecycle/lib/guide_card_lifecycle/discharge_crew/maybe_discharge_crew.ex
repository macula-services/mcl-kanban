defmodule GuideCardLifecycle.DischargeCrew.MaybeDischargeCrew do
  # Handler: the board drops a crew the realm no longer knows (#40): every
  # agent of it is discharged and the crew is recorded as discharged, in one
  # act -- one command, one list of events -- so a crash between two agent
  # discharges cannot leave half a dead crew on the board for good.
  #
  # The supervisor and the prioritiser stay: each is appointed once for the
  # whole board, not for a crew, and the desks that discharge them refuse it
  # for anyone but the owner (#29). A discharged crew keeps its seq, so a
  # replay of an old fact still never re-enlists anyone.
  #
  # Only a crew the board admitted may be discharged this way: a crew the
  # owner made has no realm entry to forget, and one already discharged has
  # nothing left to drop.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewState
  alias GuideCardLifecycle.DischargeAgent.AgentDischargedV1
  alias GuideCardLifecycle.DischargeCrew.{CrewDischargedV1, DischargeCrewV1}

  @who [:board]

  def handle_payload(state, payload), do: handle(state, struct(DischargeCrewV1, payload))

  def handle(%CrewState{} = crew, %DischargeCrewV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      CrewState.crew_name(crew, cmd.crew) == nil -> {:error, :unknown_crew}
      true -> {:ok, [CrewDischargedV1.new(cmd.by, cmd) | discharged(crew, cmd)]}
    end
  end

  def dispatch(%DischargeCrewV1{} = cmd) do
    :evoq_command.new(
      :discharge_crew,
      CrewAggregate,
      CrewAggregate.stream_id(),
      DischargeCrewV1.to_map(cmd)
    )
    |> :evoq_router.dispatch()
  end

  defp discharged(crew, cmd) do
    for node <- CrewState.agents_of(crew, cmd.crew),
        node not in [crew.supervisor, crew.prioritiser],
        do: AgentDischargedV1.new(cmd.by, node, CrewState.name_of(crew, node))
  end
end
