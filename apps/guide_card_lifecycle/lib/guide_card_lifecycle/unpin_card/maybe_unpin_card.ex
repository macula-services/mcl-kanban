defmodule GuideCardLifecycle.UnpinCard.MaybeUnpinCard do
  # Handler: only the owner unpins, and only a pinned card.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CardStatus}
  alias GuideCardLifecycle.UnpinCard.{CardUnpinnedV1, UnpinCardV1}

  @who [:owner]

  def handle_payload(state, payload), do: handle(state, struct(UnpinCardV1, payload))

  def handle(%CardState{status: status}, %UnpinCardV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      not CardStatus.pinned?(status) -> {:error, :not_pinned}
      true -> {:ok, [CardUnpinnedV1.new(cmd, :evoq_bit_flags.unset(status, CardStatus.pinned()))]}
    end
  end

  def dispatch(%UnpinCardV1{} = cmd),
    do: CardAggregate.dispatch(:unpin_card, cmd.card_id, UnpinCardV1.to_map(cmd))
end
