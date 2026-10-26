defmodule GuideCardLifecycle.UnblockCard.MaybeUnblockCard do
  # Handler: the home crew's supervisor or operator, or the owner, unblocks
  # any card on its board (#29); a held card is its holder's to unblock; a
  # card nobody holds (released while blocked) is unblocked by whoever may
  # claim it: an agent in its lane, its crew's lane, or in none (#16).
  # BLOCKED is a fact about the card, so release keeps it: the next agent
  # reads the note, unblocks, then claims. The card goes back to where it
  # was: claimed by its holder, or queued.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CardStatus, CrewName}
  alias GuideCardLifecycle.ClaimCard.MaybeClaimCard
  alias GuideCardLifecycle.UnblockCard.{CardUnblockedV1, UnblockCardV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(UnblockCardV1, payload))

  def handle(%CardState{status: status} = card, %UnblockCardV1{by: by} = cmd) do
    refusal = Actor.refused(by, @who, CrewName.home_crew_in(card))
    held = CardStatus.has?(status, CardStatus.claimed())

    cond do
      refusal == nil -> unblocked(card, cmd)
      held and Actor.holds?(by, card.holder_node_id) -> unblocked(card, cmd)
      held -> {:error, holder_refusal(refusal)}
      lane = unheld_refusal(card, by) -> {:error, lane}
      true -> unblocked(card, cmd)
    end
  end

  # Another crew's supervisor is told why it is refused; anyone else is
  # simply not the holder.
  defp holder_refusal(:not_home_crew), do: :not_home_crew
  defp holder_refusal(_not_permitted), do: :not_holder

  # Who may claim an unheld card, as MaybeClaimCard decides it.
  defp unheld_refusal(_card, %Actor{kind: kind}) when kind != :agent, do: :not_in_lane
  defp unheld_refusal(card, by), do: MaybeClaimCard.lane_refusal(card, by)

  defp unblocked(%CardState{status: status}, cmd),
    do: unblocked(CardStatus.has?(status, CardStatus.blocked()), status, cmd)

  defp unblocked(false, _status, _cmd), do: {:error, :not_blocked}

  defp unblocked(true, status, cmd),
    do: {:ok, [CardUnblockedV1.new(cmd, :evoq_bit_flags.unset(status, CardStatus.blocked()))]}

  def dispatch(%UnblockCardV1{} = cmd),
    do: CardAggregate.dispatch(:unblock_card, cmd.card_id, UnblockCardV1.to_map(cmd))
end
