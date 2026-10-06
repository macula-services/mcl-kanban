defmodule ProjectBoards.BoardOpenedV1ToBoards do
  # Projects board_opened_v1 into boards.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [project: 3]

  @impl true
  def interested_in, do: ["board_opened_v1"]

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
      {"INSERT OR IGNORE INTO boards (board_id, repo, status, opened_by, opened_at) VALUES (?, ?, 1, ?, ?)",
       [data.board_id, data.repo, data[:by], data.at]}
    ]
  end
end
