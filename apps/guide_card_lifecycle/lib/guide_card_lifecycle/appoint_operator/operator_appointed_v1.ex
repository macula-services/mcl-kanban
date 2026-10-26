defmodule GuideCardLifecycle.AppointOperator.OperatorAppointedV1 do
  # Event: operator_appointed_v1. Names the crew, so an operator's role is
  # readable from the event itself and not only from the roster it edits (#28).
  @moduledoc false

  alias GuideCardLifecycle.Actor

  def event_type, do: "operator_appointed_v1"

  def new(by, crew, node_id, name) do
    Map.merge(Actor.record(by), %{
      event_type: event_type(),
      crew: crew,
      node_id: node_id,
      name: name,
      at: System.system_time(:millisecond)
    })
  end
end
