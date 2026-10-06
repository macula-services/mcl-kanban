defmodule QueryBoards.GetCrew.GetCrew do
  # get_crew: every enlisted agent with its roles, the cards it holds now
  # (claimed or blocked) and the next card reserved to its lane.
  @moduledoc false

  alias QueryBoards.CardRows
  alias QueryBoards.GetCardsByHolder.GetCardsByHolder
  alias QueryBoards.ReadModel

  @spec get_crew() :: [map()]
  def get_crew do
    "SELECT node_id, name, roles, enlisted_at FROM crew ORDER BY name"
    |> ReadModel.q([])
    |> Enum.map(fn [node_id, name, roles, at] ->
      %{
        node_id: node_id,
        name: name,
        roles: String.split(roles, ","),
        enlisted_at: at,
        held: GetCardsByHolder.get_cards_by_holder(node_id),
        next: next_in_lane(node_id)
      }
    end)
  end

  defp next_in_lane(node_id) do
    ("WHERE c.lane_node_id = ? AND c.status & 1 = 1 AND c.status & 30 = 0 AND " <>
       CardRows.not_package_card() <>
       " ORDER BY " <>
       "c.package_rank IS NULL, c.package_rank, " <> CardRows.ladder_order() <> " LIMIT 1")
    |> CardRows.cards([node_id])
    |> List.first()
  end
end
