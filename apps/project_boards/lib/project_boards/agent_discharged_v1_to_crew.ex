defmodule ProjectBoards.AgentDischargedV1ToCrew do
  # Projects agent_discharged_v1 into crew: the row goes, and the crew it ran
  # is left without an operator.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [project: 3]

  alias ProjectBoards.Projection

  @impl true
  def interested_in, do: ["agent_discharged_v1"]

  @impl true
  def replay_policy, do: :deliver

  @impl true
  def init(_config), do: {:ok, %{}}

  @impl true
  def handle_event(type, envelope, _metadata, state) do
    with {:ok, _} <- project(type, envelope, &statements/2), do: {:ok, state}
  end

  defp statements(data, _version) do
    [
      {"DELETE FROM crew WHERE node_id = ?", [data.node_id]},
      # A discharged agent runs no crew any more (#28): the aggregate drops it
      # as operator, and the read model follows, so get_crew never names an
      # operator nobody can find in its own crew.
      {"UPDATE crews SET operator_node_id = NULL WHERE operator_node_id = ?", [data.node_id]},
      Projection.roles_sql()
    ]
  end
end
