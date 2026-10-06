defmodule GuideCardLifecycle.UnlinkCard.MaybeUnlinkCard do
  # Handler: any agent or the owner removes a link the card holds.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState}
  alias GuideCardLifecycle.UnlinkCard.{CardUnlinkedV1, UnlinkCardV1}

  @who [:agent, :owner]

  def handle_payload(state, payload), do: handle(state, struct(UnlinkCardV1, payload))

  def handle(%CardState{} = card, %UnlinkCardV1{} = cmd) do
    link = %{to_card_id: cmd.to_card_id, link: cmd.link}

    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      link not in card.links -> {:error, :not_linked}
      true -> {:ok, [CardUnlinkedV1.new(cmd, card.status, link)]}
    end
  end

  def dispatch(%UnlinkCardV1{} = cmd),
    do: CardAggregate.dispatch(:unlink_card, cmd.card_id, UnlinkCardV1.to_map(cmd))
end
