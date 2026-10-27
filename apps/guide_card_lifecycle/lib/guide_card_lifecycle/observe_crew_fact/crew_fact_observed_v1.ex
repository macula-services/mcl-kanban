defmodule GuideCardLifecycle.ObserveCrewFact.CrewFactObservedV1 do
  # Event: crew_fact_observed_v1. The realm's fact reached the board at this
  # seq, and the board acted on it (#40). The audit trail of what the realm
  # told this board, and the record the next fact is compared against.
  @moduledoc false

  alias GuideCardLifecycle.Actor

  def event_type, do: "crew_fact_observed_v1"

  def new(by, %{crew_id: crew_id, crew_name: crew_name, fact: fact, seq: seq}) do
    Map.merge(Actor.record(by), %{
      event_type: event_type(),
      crew_id: crew_id,
      crew_name: crew_name,
      fact: fact,
      seq: seq,
      at: System.system_time(:millisecond)
    })
  end
end
