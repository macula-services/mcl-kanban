defmodule ProjectBoards.GoalAdoptedV1ToCrewGoal do
  # Projects goal_adopted_v1 into crew_goal and crew_goal_packages: the one
  # goal, replacing the last (#18).
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [project: 3]

  @impl true
  def interested_in, do: ["goal_adopted_v1"]

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
      {"INSERT OR REPLACE INTO crew_goal (id, goal, adopted_by, adopted_at) VALUES (1, ?, ?, ?)",
       [data.goal, data[:by], data.at]},
      {"DELETE FROM crew_goal_packages", []}
    ] ++
      Enum.map(
        data.packages,
        &{"INSERT OR IGNORE INTO crew_goal_packages (ref) VALUES (?)", [&1]}
      )
  end
end
