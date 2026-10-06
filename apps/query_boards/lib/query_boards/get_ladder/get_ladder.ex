defmodule QueryBoards.GetLadder.GetLadder do
  # get_ladder: the owner's one view of the work. Every work package in rank
  # order (unranked last, then oldest), each with its cards in card rank
  # (unranked last, then the order they were ranked in, then age), and the
  # loose cards that sit in no package. Withdrawn cards are gone; finished
  # ones stay, so a package shows how far it got.
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
    mine = Map.get(cards, ref, [])

    %{
      package_id: id,
      issue_ref: ref,
      title: title,
      rank: nil_if(rank),
      pinned: pinned,
      ranked_by: nil_if(ranked_by),
      rationale: nil_if(rationale),
      opened_at: nil_if(opened_at),
      repos: mine |> Enum.map(& &1.board) |> Enum.uniq() |> Enum.sort(),
      cards: mine
    }
  end

  defp nil_if(:undefined), do: nil
  defp nil_if(value), do: value
end
