defmodule GuideCardLifecycle.UntagCard.MaybeUntagCard do
  # Handler: any agent or the owner. Only a tag the card holds.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState}
  alias GuideCardLifecycle.UntagCard.{CardUntaggedV1, UntagCardV1}

  @who [:agent, :owner]

  def handle_payload(state, payload), do: handle(state, struct(UntagCardV1, payload))

  def handle(%CardState{} = card, %UntagCardV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      cmd.tag not in card.tags -> {:error, :not_tagged}
      true -> {:ok, [CardUntaggedV1.new(cmd, card.status, %{tag: cmd.tag})]}
    end
  end

  def dispatch(%UntagCardV1{} = cmd),
    do: CardAggregate.dispatch(:untag_card, cmd.card_id, UntagCardV1.to_map(cmd))
end
