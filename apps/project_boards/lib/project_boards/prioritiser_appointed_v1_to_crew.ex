defmodule ProjectBoards.PrioritiserAppointedV1ToCrew do
  # Projects prioritiser_appointed_v1 into crew: one prioritiser, the appointed node.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [project: 3]

  @impl true
  def interested_in, do: ["prioritiser_appointed_v1"]

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
      {"UPDATE crew SET prioritiser = (node_id = ?)", [data.node_id]},
      {"UPDATE crew SET roles = 'agent' || CASE WHEN supervisor = 1 THEN ',supervisor' ELSE '' END || CASE WHEN prioritiser = 1 THEN ',prioritiser' ELSE '' END",
       []}
    ]
  end
end
