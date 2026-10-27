defmodule QueryBoards.GetCrew.GetCrew do
  # get_crew: every crew with its operator and its agents, each agent with its
  # roles, the cards it holds now (claimed or blocked) and the next card
  # reserved to its lane (#28). One crew per entry, so a caller reads who runs
  # a crew and who is in it without joining two answers itself.
  #
  # A crew is held by its KEY (#40 option b): its crew_id for a crew the realm
  # admitted, its name for one the owner made. The roster's `crew` column
  # holds those keys, and each entry carries its `crew_id` beside the display
  # name a person reads -- so two crews the realm admitted under one name stay
  # two entries here, and a consumer that must act on one of them has its id.
  @moduledoc false

  alias QueryBoards.CardRows
  alias QueryBoards.GetCardsByHolder.GetCardsByHolder
  alias QueryBoards.ReadModel

  @spec get_crew() :: [map()]
  def get_crew do
    operators = operators()
    names = crew_names()

    "SELECT node_id, name, crew, roles, enlisted_at FROM crew ORDER BY crew, name"
    |> ReadModel.q([])
    |> Enum.map(&agent/1)
    |> Enum.group_by(& &1.crew)
    |> Enum.sort_by(fn {key, _agents} -> {Map.get(names, key, key), key} end)
    |> Enum.map(fn {key, agents} ->
      crew_entry(key, agents, Map.get(operators, key), Map.get(names, key, key))
    end)
  end

  @doc """
  Waits (bounded) until the read model shows that node in its crew under that
  name, so an enlist's reply is followed by a read that sees the agent.
  """
  @spec await_agent(String.t(), String.t(), pos_integer()) :: :ok | {:error, :read_model_behind}
  def await_agent(node_id, name, timeout_ms \\ 5_000),
    do:
      ReadModel.await(
        "SELECT name FROM crew WHERE node_id = ?",
        [node_id],
        [[name]],
        timeout_ms
      )

  @doc """
  Waits (bounded) until the read model no longer holds that node, so a
  discharge's reply is followed by a read that no longer lists the agent. The
  node id is the projection's own key (it deletes by it), which is what makes
  this right for a discharge typed in another case than the enlist's.
  """
  @spec await_discharged(String.t(), pos_integer()) :: :ok | {:error, :read_model_behind}
  def await_discharged(node_id, timeout_ms \\ 5_000),
    do:
      ReadModel.await(
        "SELECT COUNT(*) FROM crew WHERE node_id = ?",
        [node_id],
        [[0]],
        timeout_ms
      )

  # The key comes first, then the name a person reads: an agent's own `crew` is
  # shown as the name too, since it is what the rail and the pickers print.
  defp crew_entry(key, agents, operator_node_id, name) do
    %{
      crew_id: key,
      crew: name,
      operator: who(agents, operator_node_id),
      agents: Enum.map(agents, &%{&1 | crew: name})
    }
  end

  defp who(_agents, nil), do: nil

  defp who(agents, node_id) do
    case Enum.find(agents, &(&1.node_id == node_id)) do
      nil -> %{node_id: node_id, name: nil}
      agent -> %{node_id: node_id, name: agent.name}
    end
  end

  defp agent([node_id, name, crew, roles, at]) do
    %{
      node_id: node_id,
      name: name,
      crew: crew,
      roles: String.split(roles, ","),
      enlisted_at: at,
      held: GetCardsByHolder.get_cards_by_holder(node_id),
      next: next_in_lane(node_id)
    }
  end

  defp operators do
    "SELECT name, operator_node_id FROM crews"
    |> ReadModel.q([])
    |> Map.new(fn [crew, node_id] -> {crew, node_id} end)
  end

  # The names the realm admitted its crews under, keyed by crew id. A crew the
  # owner made has no row, and its key is its name.
  defp crew_names do
    "SELECT crew_id, crew_name FROM crew_names"
    |> ReadModel.q([])
    |> Map.new(fn [crew_id, name] -> {crew_id, name} end)
  end

  defp next_in_lane(node_id) do
    ("WHERE c.lane_node_id = ? AND c.status & 1 = 1 AND c.status & 30 = 0 AND " <>
       CardRows.not_package_card() <>
       " AND " <>
       CardRows.not_deferred() <>
       " ORDER BY " <>
       "c.package_rank IS NULL, c.package_rank, " <> CardRows.ladder_order() <> " LIMIT 1")
    |> CardRows.cards([node_id])
    |> List.first()
  end
end
