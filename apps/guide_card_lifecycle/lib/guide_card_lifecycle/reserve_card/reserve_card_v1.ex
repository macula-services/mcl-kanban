defmodule GuideCardLifecycle.ReserveCard.ReserveCardV1 do
  # Command: reserve a card to the agent that owns the area (its lane). The
  # lane is named by agent name; MaybeReserveCard.dispatch/1 resolves its node
  # id from the live crew.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, AgentName, IssueRef}

  @enforce_keys [:card_id, :lane, :by]
  defstruct [:card_id, :lane, :lane_node_id, :by]

  @impl true
  def command_type, do: :reserve_card

  @impl true
  def new(%{card_id: id, lane: lane, by: %Actor{} = by} = params) do
    with {:ok, id} <- IssueRef.valid_card_id(id),
         {:ok, lane} <- lane(AgentName.name(lane)),
         do:
           {:ok,
            %__MODULE__{
              card_id: id,
              lane: lane,
              lane_node_id: Map.get(params, :lane_node_id),
              by: by
            }}
  end

  def new(_), do: {:error, :missing_required_fields}

  defp lane({:ok, name}), do: {:ok, name}
  defp lane({:error, _}), do: {:error, :unknown_agent}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
