defmodule GuideCardLifecycle.TagCard.MaybeTagCard do
  # Handler: any agent or the owner. A card holds a tag once.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState}
  alias GuideCardLifecycle.TagCard.{CardTaggedV1, TagCardV1}

  @who [:agent, :owner]

  def handle_payload(state, payload), do: handle(state, struct(TagCardV1, payload))

  def handle(%CardState{} = card, %TagCardV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      cmd.tag in card.tags -> {:error, :already_tagged}
      true -> {:ok, [CardTaggedV1.new(cmd, card.status, %{tag: cmd.tag})]}
    end
  end

  def dispatch(%TagCardV1{} = cmd),
    do: CardAggregate.dispatch(:tag_card, cmd.card_id, TagCardV1.to_map(cmd))
end
