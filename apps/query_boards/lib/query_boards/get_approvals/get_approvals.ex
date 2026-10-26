defmodule QueryBoards.GetApprovals.GetApprovals do
  # get_approvals: the signed approvals recorded on a card (#30), oldest
  # first, each with the encoded object as base64 text, so a reader in any
  # crew re-verifies it rather than trusting this board.
  @moduledoc false

  alias QueryBoards.ReadModel

  @spec get_approvals(String.t()) :: {:ok, [map()]} | {:error, :unknown_card}
  def get_approvals(card_id) when is_binary(card_id),
    do: of_card(ReadModel.q("SELECT 1 FROM cards WHERE card_id = ?", [card_id]), card_id)

  def get_approvals(_), do: {:error, :unknown_card}

  defp of_card([], _card_id), do: {:error, :unknown_card}

  defp of_card(_known, card_id) do
    {:ok,
     ("SELECT kind, verdict, operator_node_id, repo, ref, base, tip, tag, issue, signed_at, nonce, " <>
        "recorded_by, recorded_at, approval FROM card_approvals WHERE card_id = ? ORDER BY recorded_at, nonce")
     |> ReadModel.q([card_id])
     |> Enum.map(&approval/1)}
  end

  defp approval([
         kind,
         verdict,
         operator,
         repo,
         ref,
         base,
         tip,
         tag,
         issue,
         signed_at,
         nonce,
         by,
         at,
         approval
       ]) do
    %{
      kind: kind,
      verdict: verdict,
      operator_node_id: operator,
      repo: repo,
      ref: ref,
      base: base,
      tip: tip,
      tag: tag,
      issue: issue,
      signed_at: signed_at,
      nonce: nonce,
      recorded_by: by,
      recorded_at: at,
      approval: approval
    }
  end
end
