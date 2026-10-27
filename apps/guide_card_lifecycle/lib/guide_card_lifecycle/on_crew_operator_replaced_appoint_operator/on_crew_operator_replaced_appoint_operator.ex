defmodule GuideCardLifecycle.OnCrewOperatorReplacedAppointOperator do
  # PM: the realm replaced a crew's operator, so this board appoints the new
  # one and drops the previous one (#40, threat model R4). The previous
  # operator's NAME is the board's own, read from its roster by the node id
  # the fact carries: the realm names the one it removed, not the board's
  # name for it.
  @moduledoc false

  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewFacts.RealmActs
  alias GuideCardLifecycle.CrewState

  @spec handle(map()) :: {:ok, map()}
  def handle(payload) do
    crew = payload["crew_name"]
    node = payload["operator_node"]
    previous = payload["previous_operator_node"]

    enlisted = RealmActs.enlist(crew, {node, payload["operator_name"]})
    operator = RealmActs.appoint(crew, payload["operator_name"])

    {:ok,
     %{enlisted: enlisted, operator: operator, previous: drop_previous(crew, previous, node)}}
  end

  # A re-appointment names the operator already sitting as the previous one:
  # nothing to drop. A node this board never held has nothing here to drop
  # either; the realm's own record is the one that says it was replaced.
  defp drop_previous(_crew, previous, previous), do: :ok

  defp drop_previous(crew, previous, _node) do
    held = CrewState.crew_of(CrewAggregate.current(), previous) == crew

    if held, do: RealmActs.discharge(previous), else: :ok
  end
end
