defmodule QueryBoards.GetNextCardForAgent.GetNextCardForAgent do
  # get_next_card_for_agent: the cards an agent may claim next, best first.
  # The crew goal's packages first (#18); within that and the rest, its own
  # lane first, then unreserved cards; within each, in ladder order:
  # cards in a package by the package's rank (unranked packages after ranked
  # ones, loose cards after every package), then by card rank (unranked
  # last), then the order they were ranked in, then oldest. Only queued cards
  # that are not blocked, not deferred (#17) and not a package's own card
  # (#15: never claimed),
  # on boards not known to be archived (the board's row
  # and the card's land through different projections, so a card may arrive
  # before its board).
  #
  # This is a candidate list: claim_next_card claims down it, because another
  # agent may take a card between this read and the claim.
  @moduledoc false

  alias QueryBoards.CardRows

  @spec get_next_card_for_agent(String.t(), pos_integer()) :: [map()]
  def get_next_card_for_agent(node_id, limit) when is_binary(node_id) and is_integer(limit) do
    claimable =
      Enum.join(
        [
          "c.status & 1 = 1 AND c.status & 30 = 0",
          "(b.status IS NULL OR b.status & 2 = 0)",
          "(c.lane_node_id IS NULL OR c.lane_node_id = ?)",
          CardRows.not_package_card(),
          CardRows.not_deferred()
        ],
        " AND "
      )

    CardRows.cards(
      "LEFT JOIN boards b ON b.board_id = c.board_id WHERE #{claimable} " <>
        "ORDER BY #{off_goal()}, c.lane_node_id IS NULL, c.work_package IS NULL, c.package_rank IS NULL, " <>
        "c.package_rank, " <> CardRows.ladder_order() <> " LIMIT ?",
      [node_id, limit]
    )
  end

  # The crew's goal comes first (#18): its packages' cards, in the caller's
  # lane first, then unreserved; then the caller's lane; then the rest. A
  # reservation says who may do a card, not when (Fable's advice).
  defp off_goal,
    do: "(c.work_package IS NULL OR c.work_package NOT IN (SELECT ref FROM crew_goal_packages))"
end
