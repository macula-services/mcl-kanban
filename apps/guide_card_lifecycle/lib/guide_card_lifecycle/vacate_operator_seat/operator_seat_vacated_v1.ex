defmodule GuideCardLifecycle.VacateOperatorSeat.OperatorSeatVacatedV1 do
  # Event: operator_seat_vacated_v1. The crew's operator seat is empty (#40).
  # Names the crew, so the seat that emptied is readable from the event itself
  # and not only from the roster it edits.
  @moduledoc false

  alias GuideCardLifecycle.Actor

  def event_type, do: "operator_seat_vacated_v1"

  def new(by, crew) do
    Map.merge(Actor.record(by), %{
      event_type: event_type(),
      crew: crew,
      at: System.system_time(:millisecond)
    })
  end
end
