defmodule GuideCardLifecycle.LinkCard.MaybeLinkCard do
  # Handler: any agent or the owner links. A link is held once. The other
  # card must exist; that is checked against its live aggregate before
  # dispatch.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState}
  alias GuideCardLifecycle.LinkCard.{CardLinkedV1, LinkCardV1}

  @who [:agent, :owner]

  def handle_payload(state, payload), do: handle(state, struct(LinkCardV1, payload))

  def handle(%CardState{} = card, %LinkCardV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      link(cmd) in card.links -> {:error, :already_linked}
      true -> {:ok, [CardLinkedV1.new(cmd, card.status, link(cmd))]}
    end
  end

  defp link(cmd), do: %{to_card_id: cmd.to_card_id, link: cmd.link}

  def dispatch(%LinkCardV1{} = cmd) do
    case CardAggregate.current(cmd.to_card_id) do
      %CardState{status: 0} -> {:error, :unknown_card}
      %CardState{} -> CardAggregate.dispatch(:link_card, cmd.card_id, LinkCardV1.to_map(cmd))
    end
  end
end
