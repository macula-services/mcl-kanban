defmodule ProjectBoards.AgentDischargedV1ToCrew do
  # Projects agent_discharged_v1 into crew: the row goes.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [project: 3]

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

  defp statements(data, _version), do: [{"DELETE FROM crew WHERE node_id = ?", [data.node_id]}]
end
