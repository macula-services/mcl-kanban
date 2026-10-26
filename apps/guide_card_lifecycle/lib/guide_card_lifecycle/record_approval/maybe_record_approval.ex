defmodule GuideCardLifecycle.RecordApproval.MaybeRecordApproval do
  # Handler: any enlisted agent brings an approval to the card; the signature
  # is the authority, not the caller (#30). The approval is recorded only when
  # it names this card and its repo (and, for a gate, its issue), its signer is the operator of the card's
  # home crew right now, and its nonce is new on this card. The nonce is kept
  # per card, which is enough because the card id is signed: a yes for one
  # card is wrong_card on every other.
  #
  # Recorded on a finished card too: a release is often approved after its
  # card is done.
  @moduledoc false

  alias GuideCardLifecycle.{
    Actor,
    BoardAggregate,
    CardAggregate,
    CardState,
    CrewAggregate,
    CrewName,
    CrewState
  }

  alias GuideCardLifecycle.RecordApproval.{ApprovalRecordedV1, RecordApprovalV1}

  @who [:agent]

  def handle_payload(state, payload), do: handle(state, struct(RecordApprovalV1, payload))

  def handle(%CardState{} = card, %RecordApprovalV1{} = cmd) do
    case refused(card, cmd) do
      nil -> {:ok, [ApprovalRecordedV1.new(cmd, card.status)]}
      refusal -> {:error, refusal}
    end
  end

  defp refused(card, cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> :not_permitted
      cmd.approval_card_id != card.card_id -> :wrong_card
      cmd.repo != card.repo -> :wrong_repo
      other_issue?(card, cmd) -> :wrong_issue
      not operator?(cmd.home_operator, cmd.operator_node_id) -> :not_home_operator
      MapSet.member?(card.approval_nonces, cmd.nonce) -> :replayed_nonce
      true -> nil
    end
  end

  # The card is one issue (its id is that issue's digest), so a gate passes
  # on the card only when it names that issue.
  defp other_issue?(card, %{kind: "gate:" <> _, issue: issue}), do: issue != card.issue_ref
  defp other_issue?(_card, _range), do: false

  defp operator?(home_operator, signer), do: is_binary(home_operator) and home_operator == signer

  @doc "Dispatches with the operator of the card's home crew, read live."
  def dispatch(%RecordApprovalV1{} = cmd) do
    payload = %{RecordApprovalV1.to_map(cmd) | home_operator: home_operator(cmd.card_id)}
    CardAggregate.dispatch(:record_approval, cmd.card_id, payload)
  end

  defp home_operator(card_id) do
    card = CardAggregate.current(card_id)
    CrewState.operator_of(CrewAggregate.current(), board_crew(card))
  end

  defp board_crew(%CardState{board_id: nil} = card), do: CrewName.home_crew_in(card)
  defp board_crew(%CardState{board_id: id}), do: BoardAggregate.current(id).home_crew
end
