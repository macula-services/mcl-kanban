defmodule QueryBoards.GetCrew.GetCrew do
  # get_crew: every crew with its operator and its agents, each agent with its
  # roles, the cards it holds now (claimed or blocked) and the next card
  # reserved to its lane (#28). One crew per entry, so a caller reads who runs
  # a crew and who is in it without joining two answers itself.
  @moduledoc false

  alias QueryBoards.CardRows
  alias QueryBoards.GetCardsByHolder.GetCardsByHolder
  alias QueryBoards.ReadModel

  @spec get_crew() :: [map()]
  def get_crew do
    operators = operators()

    "SELECT node_id, name, crew, roles, enlisted_at FROM crew ORDER BY crew, name"
    |> ReadModel.q([])
    |> Enum.map(&agent/1)
    |> Enum.group_by(& &1.crew)
    |> Enum.sort_by(fn {crew, _agents} -> crew end)
    |> Enum.map(fn {crew, agents} -> crew_entry(crew, agents, Map.get(operators, crew)) end)
  end

  defp crew_entry(crew, agents, operator_node_id) do
    %{crew: crew, operator: who(agents, operator_node_id), agents: agents}
  end

  defp who(_agents, nil), do: nil

  defp who(agents, node_id) do
    case Enum.find(agents, &(&1.node_id == node_id)) do
      nil -> %{node_id: node_id, name: nil}
      agent -> %{node_id: node_id, name: agent.name}
    end
  end

  defp agent([node_id, name, crew, roles, at]) do
    %{
      node_id: node_id,
      name: name,
      crew: crew,
      roles: String.split(roles, ","),
      enlisted_at: at,
      held: GetCardsByHolder.get_cards_by_holder(node_id),
      next: next_in_lane(node_id)
    }
  end

  defp operators do
    "SELECT name, operator_node_id FROM crews"
    |> ReadModel.q([])
    |> Map.new(fn [crew, node_id] -> {crew, node_id} end)
  end

  defp next_in_lane(node_id) do
    ("WHERE c.lane_node_id = ? AND c.status & 1 = 1 AND c.status & 30 = 0 AND " <>
       CardRows.not_package_card() <>
       " AND " <>
       CardRows.not_deferred() <>
       " ORDER BY " <>
       "c.package_rank IS NULL, c.package_rank, " <> CardRows.ladder_order() <> " LIMIT 1")
    |> CardRows.cards([node_id])
    |> List.first()
  end
end
