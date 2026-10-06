defmodule QueryBoards.GetLadder.GetLadder do
  # get_ladder: the owner's one view of the work. Every work package in rank
  # order (unranked last, then oldest), each with its cards in card rank
  # (unranked last, then the order they were ranked in, then age), and the
  # loose cards that sit in no package. Withdrawn cards are gone; finished
  # ones stay, so a package shows how far it got.
  #
  # A package's own card heads it (#15): never one of its cards and never
  # counted. A package is done (1) when it has cards and every one is
  # finished; the board works that out, nobody claims or finishes a package.
  @moduledoc false

  alias QueryBoards.CardRows
  alias QueryBoards.ReadModel

  @spec get_ladder() :: %{packages: [map()], loose: [map()]}
  def get_ladder do
    cards =
      CardRows.cards("WHERE c.status & 16 = 0 ORDER BY " <> CardRows.ladder_order(), [])
      |> Enum.group_by(& &1.work_package)

    packages =
      ("SELECT package_id, issue_ref, title, rank, pinned, ranked_by, rationale, opened_at FROM packages " <>
         "ORDER BY rank IS NULL, rank, opened_at")
      |> ReadModel.q([])
      |> Enum.map(&package(&1, cards))

    %{packages: packages, loose: Map.get(cards, nil, [])}
  end

  defp package([id, ref, title, rank, pinned, ranked_by, rationale, opened_at], cards) do
    mine = cards |> Map.get(ref, []) |> Enum.reject(&(&1.package_card == 1))

    %{
      package_id: id,
      issue_ref: ref,
      title: title,
      rank: rank,
      pinned: pinned,
      ranked_by: ranked_by,
      rationale: rationale,
      opened_at: opened_at,
      repos: mine |> Enum.map(& &1.board) |> Enum.uniq() |> Enum.sort(),
      cards: mine,
      done: done(mine)
    }
  end

  defp done([]), do: 0
  defp done(cards), do: cards |> Enum.all?(&(&1.state == "finished")) |> one_or_zero()

  defp one_or_zero(true), do: 1
  defp one_or_zero(false), do: 0
end
