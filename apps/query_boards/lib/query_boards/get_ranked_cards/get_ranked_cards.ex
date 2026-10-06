defmodule QueryBoards.GetRankedCards.GetRankedCards do
  # get_ranked_cards: every open card on every board in the one global rank
  # order (unranked last, then oldest), for the owner's all-boards view.
  @moduledoc false

  alias QueryBoards.CardRows

  @spec get_ranked_cards() :: [map()]
  def get_ranked_cards,
    do:
      CardRows.cards(
        "WHERE c.status & 24 = 0 AND " <>
          CardRows.not_package_card() <>
          " AND " <> CardRows.not_deferred() <> " ORDER BY c.rank IS NULL, c.rank, c.queued_at",
        []
      )
end
