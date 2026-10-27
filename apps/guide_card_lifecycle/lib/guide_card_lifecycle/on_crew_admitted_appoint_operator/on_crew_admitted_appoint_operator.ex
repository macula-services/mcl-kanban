defmodule GuideCardLifecycle.OnCrewAdmittedAppointOperator do
  # PM: the realm admitted a crew, so this board enlists its members and
  # appoints its operator (#40, threat model R4). The realm is the outside
  # agreement that a crew exists; only the consumer that verified its
  # signature dispatches this, and every act here is the realm's own.
  #
  # The operator is enlisted too when the realm did not list it among the
  # members: appointing names an agent of the crew, and a board can only
  # appoint one it holds.
  #
  # The fact carries the whole roster, so an agent this board holds in the
  # crew and the fact does not name is dropped: a re-sent admission with a
  # smaller roster is the realm saying that member is gone (#40).
  #
  # The crew every act here names is the fact's `crew_id` (#40 option b): the
  # realm's id for the crew, which is what the board holds that crew's agents,
  # its operator and its seq under.
  @moduledoc false

  alias GuideCardLifecycle.CrewFacts.RealmActs

  @spec handle(map()) :: {:ok, map()}
  def handle(payload) do
    crew = payload["crew_id"]

    enlisted = for member <- members(payload), do: {member, RealmActs.enlist(crew, member)}
    operator = RealmActs.appoint(crew, payload["operator_name"])
    dropped = RealmActs.drop_not_kept(crew, kept(payload))

    {:ok, %{enlisted: enlisted, operator: operator, dropped: dropped}}
  end

  # The nodes the fact keeps: every member the realm attested, plus the
  # operator when it is not among them.
  defp kept(payload), do: payload["member_nodes"] ++ [payload["operator_node"]]

  # Every member with the name the realm attested, plus the operator when it
  # is not among them.
  defp members(payload) do
    members =
      for node <- payload["member_nodes"], do: {node, Map.fetch!(payload["member_names"], node)}

    operator = {payload["operator_node"], payload["operator_name"]}

    if List.keymember?(members, elem(operator, 0), 0), do: members, else: members ++ [operator]
  end
end
