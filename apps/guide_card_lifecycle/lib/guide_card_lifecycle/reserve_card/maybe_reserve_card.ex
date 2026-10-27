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

  @doc "Resolves the lane's node id, or the crew, from the live crew, then dispatches."
  def dispatch(%ReserveCardV1{crew: crew} = cmd) when is_binary(crew) do
    live = CrewAggregate.current()

    # The crew a person names is resolved to its KEY (#40 option b), as
    # enlisting resolves one, so a lane can be reserved for a crew the realm
    # admitted: its agents claim by the key they are held under.
    with {:ok, key} <- CrewState.crew_key_for(live, crew),
         do: crew_reserved(key in CrewState.crew_keys(live), %{cmd | crew: key})
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
