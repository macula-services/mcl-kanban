defmodule QueryBoards.GetCardsByHolder.GetCardsByHolder do
  # get_cards_by_holder: the cards an agent holds now (claimed or blocked,
  # not finished or withdrawn), by node id.
  @moduledoc false

  alias QueryBoards.CardRows

  @spec get_cards_by_holder(String.t()) :: [map()]
  def get_cards_by_holder(node_id) when is_binary(node_id) do
    CardRows.cards(
      "WHERE c.holder_node_id = ? AND c.status & 2 = 2 AND c.status & 24 = 0 ORDER BY c.claimed_at",
      [node_id]
    )
  end
end
