defmodule GuideCardLifecycle.ReclassifyCard.MaybeReclassifyCard do
  # Handler: the supervisor or the owner reclassifies.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState}
  alias GuideCardLifecycle.ReclassifyCard.{CardReclassifiedV1, ReclassifyCardV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(ReclassifyCardV1, payload))

  def handle(%CardState{} = card, %ReclassifyCardV1{} = cmd) do
    case Actor.allowed?(cmd.by, @who) do
      true -> {:ok, [CardReclassifiedV1.new(cmd, card.status, %{kind: cmd.kind})]}
      false -> {:error, :not_permitted}
    end
  end

  def dispatch(%ReclassifyCardV1{} = cmd),
    do: CardAggregate.dispatch(:reclassify_card, cmd.card_id, ReclassifyCardV1.to_map(cmd))
end
