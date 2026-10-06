defmodule GuideCardLifecycle.ReserveCard.MaybeReserveCard do
  # Handler: the supervisor, the prioritiser or the owner reserves a card to
  # an enlisted agent's lane. Only that agent may then claim it.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CrewAggregate, CrewState}
  alias GuideCardLifecycle.ReserveCard.{CardReservedV1, ReserveCardV1}

  @who [:supervisor, :prioritiser, :owner]

  def handle_payload(state, payload), do: handle(state, struct(ReserveCardV1, payload))

  def handle(%CardState{} = card, %ReserveCardV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) ->
        {:error, :not_permitted}

      not is_binary(cmd.lane_node_id) ->
        {:error, :unknown_agent}

      true ->
        {:ok,
         [CardReservedV1.new(cmd, card.status, %{lane: cmd.lane, lane_node_id: cmd.lane_node_id})]}
    end
  end

  @doc "Resolves the lane's node id from the live crew, then dispatches."
  def dispatch(%ReserveCardV1{} = cmd) do
    crew = CrewAggregate.current()
    reserved(CrewState.node_id_of(crew, cmd.lane), crew, cmd)
  end

  defp reserved(nil, _crew, _cmd), do: {:error, :unknown_agent}

  defp reserved(node_id, crew, cmd) do
    cmd = %{cmd | lane: CrewState.name_of(crew, node_id), lane_node_id: node_id}
    CardAggregate.dispatch(:reserve_card, cmd.card_id, ReserveCardV1.to_map(cmd))
  end
end
