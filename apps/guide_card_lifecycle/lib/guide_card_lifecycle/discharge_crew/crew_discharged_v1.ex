defmodule GuideCardLifecycle.DischargeCrew.CrewDischargedV1 do
  # Event: crew_discharged_v1. The board dropped a crew the realm stopped
  # knowing (#40), with the board's reason for it. The agents' own discharges
  # are written beside it in the same act, so the roster and this record always
  # agree about who lost the board.
  @moduledoc false

  alias GuideCardLifecycle.Actor

  def event_type, do: "crew_discharged_v1"

  def new(by, %{crew: crew, reason: reason}) do
    Map.merge(Actor.record(by), %{
      event_type: event_type(),
      crew: crew,
      reason: reason,
      at: System.system_time(:millisecond)
    })
  end
end
