defmodule GuideCardLifecycle.OnCrewOperatorReplacedAppointOperator do
  # PM: the realm replaced a crew's operator, so this board appoints the new
  # one and drops whoever the fact no longer names (#40, threat model R4). A
  # discharge names an agent by the board's own name for it, read from the
  # roster by node id: the realm names the node it removed, never the board's
  # name for it.
  @moduledoc false

  alias GuideCardLifecycle.CrewFacts.RealmActs

  @spec handle(map()) :: {:ok, map()}
  def handle(payload) do
    crew = payload["crew_id"]
    node = payload["operator_node"]

    enlisted = RealmActs.enlist(crew, {node, payload["operator_name"]})
    operator = RealmActs.appoint(crew, payload["operator_name"])
    dropped = RealmActs.drop_not_kept(crew, kept(payload))

    {:ok, %{enlisted: enlisted, operator: operator, dropped: dropped}}
  end

  # The nodes the fact keeps: the whole roster it carries, which is the
  # realm's own record of who is still in the crew. A replaced operator is not
  # in it unless the realm re-enrolled it, and the members the realm dropped
  # with it are not either: discharging only `previous_operator_node` would
  # leave every other dropped member acting for the crew.
  defp kept(payload), do: payload["member_nodes"] ++ [payload["operator_node"]]
end
