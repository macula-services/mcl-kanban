defmodule GuideCardLifecycle.ReclassifyCard.MaybeReclassifyCard do
  # Handler: the home crew's supervisor or operator, or the owner,
  # reclassifies (#29).
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CrewName}
  alias GuideCardLifecycle.ReclassifyCard.{CardReclassifiedV1, ReclassifyCardV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(ReclassifyCardV1, payload))

  def handle(%CardState{} = card, %ReclassifyCardV1{} = cmd) do
    case Actor.refused(cmd.by, @who, CrewName.home_crew_in(card)) do
      nil -> {:ok, [CardReclassifiedV1.new(cmd, card.status, %{kind: cmd.kind})]}
      refusal -> {:error, refusal}
    end
  end

  def dispatch(%ReclassifyCardV1{} = cmd),
    do: CardAggregate.dispatch(:reclassify_card, cmd.card_id, ReclassifyCardV1.to_map(cmd))
end
