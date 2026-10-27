defmodule GuideCardLifecycle.ObserveCrewFact.MaybeObserveCrewFact do
  # Handler: record that the board accepted the realm's crew fact at `seq`
  # (#40). Only the realm's actor writes this, and only upward: a fact at the
  # seq already seen -- a replay, or the same fact arriving twice -- is
  # refused, which is what stops an old `admitted` from re-appointing a crew
  # that has since been revoked.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewState
  alias GuideCardLifecycle.ObserveCrewFact.{CrewFactObservedV1, ObserveCrewFactV1}

  def handle_payload(state, payload), do: handle(state, struct(ObserveCrewFactV1, payload))

  def handle(%CrewState{} = crew, %ObserveCrewFactV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, [:realm]) -> {:error, :not_permitted}
      cmd.seq <= CrewState.crew_seq(crew, cmd.crew_id) -> {:error, :already_observed}
      true -> {:ok, [CrewFactObservedV1.new(cmd.by, cmd)]}
    end
  end

  def dispatch(%ObserveCrewFactV1{} = cmd) do
    :evoq_command.new(
      :observe_crew_fact,
      CrewAggregate,
      CrewAggregate.stream_id(),
      ObserveCrewFactV1.to_map(cmd)
    )
    |> :evoq_router.dispatch()
  end
end
