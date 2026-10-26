defmodule GuideCardLifecycle.RewordCard.MaybeRewordCard do
  # Handler: the home crew's supervisor or operator, the owner, or the card's
  # holder when it is of the home crew, rewords it (#29): an agent of another
  # crew may hold the card and work it, not rewrite what it asks for.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CrewName}
  alias GuideCardLifecycle.RewordCard.{CardRewordedV1, RewordCardV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(RewordCardV1, payload))

  def handle(%CardState{} = card, %RewordCardV1{by: by} = cmd) do
    case reword_refused(by, card) do
      nil -> {:ok, [CardRewordedV1.new(cmd, card.status, %{title: cmd.title, story: cmd.story})]}
      refusal -> {:error, refusal}
    end
  end

  # The holder passes the role half of the gate, never the crew half.
  defp reword_refused(by, card) do
    home = CrewName.home_crew_in(card)
    holds = Actor.holds?(by, card.holder_node_id)
    held_refusal(holds, by.crew == home, Actor.refused(by, @who, home))
  end

  defp held_refusal(true, true, _refusal), do: nil
  defp held_refusal(true, false, :not_permitted), do: :not_home_crew
  defp held_refusal(_holds, _home, refusal), do: refusal

  def dispatch(%RewordCardV1{} = cmd),
    do: CardAggregate.dispatch(:reword_card, cmd.card_id, RewordCardV1.to_map(cmd))
end
