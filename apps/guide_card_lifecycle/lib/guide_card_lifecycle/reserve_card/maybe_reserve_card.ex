defmodule GuideCardLifecycle.ReserveCard.MaybeReserveCard do
  # Handler: the home crew's supervisor, prioritiser or operator, or the
  # owner, reserves a card to an enlisted agent's lane, or to a crew's (#29).
  # Only that agent, or an agent of that crew, may then claim it. The home
  # crew may reserve its card to an agent or crew of another crew: that is
  # how it hands work over.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CrewAggregate, CrewName, CrewState}
  alias GuideCardLifecycle.ReserveCard.{CardReservedV1, ReserveCardV1}

  @who [:supervisor, :prioritiser, :owner]

  def handle_payload(state, payload), do: handle(state, struct(ReserveCardV1, payload))

  def handle(%CardState{} = card, %ReserveCardV1{} = cmd) do
    cond do
      refusal = Actor.refused(cmd.by, @who, CrewName.home_crew_in(card)) ->
        {:error, refusal}

      is_binary(cmd.crew) ->
        {:ok,
         [
           CardReservedV1.new(cmd, card.status, %{
             lane: nil,
             lane_node_id: nil,
             lane_crew: cmd.crew
           })
         ]}

      not is_binary(cmd.lane_node_id) ->
        {:error, :unknown_agent}

      true ->
        {:ok,
         [
           CardReservedV1.new(cmd, card.status, %{
             lane: cmd.lane,
             lane_node_id: cmd.lane_node_id,
             lane_crew: nil
           })
         ]}
    end
  end

  @doc "Checks the crew is one the roster knows, then dispatches."
  def dispatch(%ReserveCardV1{crew: crew} = cmd) when is_binary(crew) do
    live = CrewAggregate.current()

    # The crew a person picks is a KEY (#40 option b), as enlisting's is: a
    # bare name for a crew the board's owner made, a 64-hex `crew_id` for one
    # the realm admitted, so a lane can be reserved for a realm crew too. It is
    # never resolved from a name.
    crew_reserved(crew in CrewState.crew_keys(live), cmd)
  end

  def dispatch(%ReserveCardV1{} = cmd) do
    crew = CrewAggregate.current()
    reserved(CrewState.node_id_of(crew, cmd.lane), crew, cmd)
  end

  defp crew_reserved(false, _cmd), do: {:error, :unknown_crew}

  defp crew_reserved(true, cmd),
    do: CardAggregate.dispatch(:reserve_card, cmd.card_id, ReserveCardV1.to_map(cmd))

  defp reserved(nil, _crew, _cmd), do: {:error, :unknown_agent}

  defp reserved(node_id, crew, cmd) do
    cmd = %{cmd | lane: CrewState.name_of(crew, node_id), lane_node_id: node_id}
    CardAggregate.dispatch(:reserve_card, cmd.card_id, ReserveCardV1.to_map(cmd))
  end
end
