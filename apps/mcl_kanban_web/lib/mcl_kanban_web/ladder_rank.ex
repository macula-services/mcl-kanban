defmodule MclKanbanWeb.LadderRank do
  # Where a card the owner drags lands on the one rank scale: a rank between
  # its new neighbours (after_id above it, before_id below it), so the move is
  # ONE owner prioritise_card and no other card is touched or pinned. Equal
  # ranks keep the order they were ranked in (the ladder orders by ranked_at),
  # so a card given its upper neighbour's rank sits right after it.
  #
  # ranks maps every card on the ladder to its rank, nil for unranked.
  @moduledoc false

  @spec place(%{String.t() => non_neg_integer() | nil}, String.t() | nil, String.t() | nil) ::
          {:ok, non_neg_integer()} | {:error, :unranked_target | :unknown_card}
  def place(ranks, after_id, before_id) do
    with {:ok, above} <- rank_of(ranks, after_id),
         {:ok, below} <- rank_of(ranks, before_id),
         do: between(above, below, after_id)
  end

  defp rank_of(_ranks, nil), do: {:ok, :edge}
  defp rank_of(ranks, id) when is_map_key(ranks, id), do: {:ok, Map.fetch!(ranks, id)}
  defp rank_of(_ranks, _id), do: {:error, :unknown_card}

  defp between(nil, _below, after_id) when is_binary(after_id), do: {:error, :unranked_target}
  defp between(:edge, below, _after_id) when below in [:edge, nil], do: {:ok, 0}
  defp between(:edge, below, _after_id), do: {:ok, max(below - 1, 0)}
  defp between(above, below, _after_id) when below in [:edge, nil], do: {:ok, above + 1}

  defp between(above, below, _after_id) when below - above >= 2,
    do: {:ok, above + div(below - above, 2)}

  defp between(above, _below, _after_id), do: {:ok, above}
end
