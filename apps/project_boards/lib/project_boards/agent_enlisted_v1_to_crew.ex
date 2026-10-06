defmodule ProjectBoards.AgentEnlistedV1ToCrew do
  # Projects agent_enlisted_v1 into crew.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [project: 3]

  @impl true
  def interested_in, do: ["agent_enlisted_v1"]

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
      {"INSERT OR REPLACE INTO crew (node_id, name, supervisor, prioritiser, roles, enlisted_at) VALUES (?, ?, 0, 0, 'agent', ?)",
       [data.node_id, data.name, data.at]}
    ]
  end
end
