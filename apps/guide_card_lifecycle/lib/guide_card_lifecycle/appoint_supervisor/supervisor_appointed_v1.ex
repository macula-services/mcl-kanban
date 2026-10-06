defmodule GuideCardLifecycle.AppointSupervisor.SupervisorAppointedV1 do
  # Event: supervisor_appointed_v1.
  @moduledoc false

  alias GuideCardLifecycle.Actor

  def event_type, do: "supervisor_appointed_v1"

  def new(by, node_id, name) do
    Map.merge(Actor.record(by), %{
      event_type: event_type(),
      node_id: node_id,
      name: name,
      at: System.system_time(:millisecond)
    })
  end
end
