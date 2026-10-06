defmodule GuideCardLifecycle.UnblockCard.MaybeUnblockCard do
  # Handler: the holder, the supervisor or the owner unblocks. The card goes
  # back to where it was: claimed by its holder, or queued.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CardStatus}
  alias GuideCardLifecycle.UnblockCard.{CardUnblockedV1, UnblockCardV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(UnblockCardV1, payload))

  def handle(%CardState{status: status} = card, %UnblockCardV1{by: by} = cmd) do
    cond do
      not (Actor.allowed?(by, @who) or Actor.holds?(by, card.holder_node_id)) ->
        {:error, :not_holder}

      not CardStatus.has?(status, CardStatus.blocked()) ->
        {:error, :not_blocked}

      true ->
        {:ok, [CardUnblockedV1.new(cmd, :evoq_bit_flags.unset(status, CardStatus.blocked()))]}
    end
  end

  def dispatch(%UnblockCardV1{} = cmd),
    do: CardAggregate.dispatch(:unblock_card, cmd.card_id, UnblockCardV1.to_map(cmd))
end
