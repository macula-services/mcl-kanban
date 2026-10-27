defmodule GuideCardLifecycle.ReserveCard.ReserveCardV1 do
  # Command: reserve a card to the agent that owns the area (its lane), or to
  # a crew (#29): exactly one of the two. The lane is named by agent name;
  # MaybeReserveCard.dispatch/1 resolves its node id from the live crew, and
  # checks a crew is one the roster knows.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, AgentName, CrewName, IssueRef}

  @enforce_keys [:card_id, :by]
  defstruct [:card_id, :lane, :lane_node_id, :crew, :by]

  @impl true
  def command_type, do: :reserve_card

  @impl true
  def new(%{card_id: _, lane: lane, crew: crew, by: %Actor{}}) when lane != nil and crew != nil,
    do: {:error, :one_lane}

  def new(%{card_id: id, lane: lane, by: %Actor{} = by} = params) when lane != nil do
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

  def new(%{card_id: id, crew: crew, by: %Actor{} = by}) when crew != nil do
    with {:ok, id} <- IssueRef.valid_card_id(id),
         {:ok, crew} <- CrewName.key(crew),
         do: {:ok, %__MODULE__{card_id: id, crew: crew, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  defp lane({:ok, name}), do: {:ok, name}
  defp lane({:error, _}), do: {:error, :unknown_agent}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
