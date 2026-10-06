defmodule GuideCardLifecycle.RewordCard.MaybeRewordCard do
  # Handler: the supervisor, the owner or the card's holder rewords it.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState}
  alias GuideCardLifecycle.RewordCard.{CardRewordedV1, RewordCardV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(RewordCardV1, payload))

  def handle(%CardState{} = card, %RewordCardV1{by: by} = cmd) do
    case Actor.allowed?(by, @who) or Actor.holds?(by, card.holder_node_id) do
      true -> {:ok, [CardRewordedV1.new(cmd, card.status, %{title: cmd.title, story: cmd.story})]}
      false -> {:error, :not_permitted}
    end
  end

  def dispatch(%RewordCardV1{} = cmd),
    do: CardAggregate.dispatch(:reword_card, cmd.card_id, RewordCardV1.to_map(cmd))
end
