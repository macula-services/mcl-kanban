defmodule GuideCardLifecycle.UnblockCard.MaybeUnblockCard do
  # Handler: the supervisor or the owner unblocks any card; a held card is
  # its holder's to unblock; a card nobody holds (released while blocked) is
  # unblocked by whoever may claim it, an agent in its lane or in none (#16).
  # BLOCKED is a fact about the card, so release keeps it: the next agent
  # reads the note, unblocks, then claims. The card goes back to where it
  # was: claimed by its holder, or queued.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CardStatus}
  alias GuideCardLifecycle.UnblockCard.{CardUnblockedV1, UnblockCardV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(UnblockCardV1, payload))

  def handle(%CardState{status: status} = card, %UnblockCardV1{by: by} = cmd) do
    cond do
      Actor.allowed?(by, @who) ->
        unblocked(card, cmd)

      CardStatus.has?(status, CardStatus.claimed()) and not Actor.holds?(by, card.holder_node_id) ->
        {:error, :not_holder}

      not CardStatus.has?(status, CardStatus.claimed()) and not may_claim?(card, by) ->
        {:error, :not_in_lane}

      true ->
        unblocked(card, cmd)
    end
  end

  # Who may claim an unheld card, as MaybeClaimCard decides it.
  defp may_claim?(card, by), do: by.kind == :agent and card.lane_node_id in [nil, by.node_id]

  defp unblocked(%CardState{status: status}, cmd),
    do: unblocked(CardStatus.has?(status, CardStatus.blocked()), status, cmd)

  defp unblocked(false, _status, _cmd), do: {:error, :not_blocked}

  defp unblocked(true, status, cmd),
    do: {:ok, [CardUnblockedV1.new(cmd, :evoq_bit_flags.unset(status, CardStatus.blocked()))]}

  def dispatch(%UnblockCardV1{} = cmd),
    do: CardAggregate.dispatch(:unblock_card, cmd.card_id, UnblockCardV1.to_map(cmd))
end
