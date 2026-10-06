defmodule ProjectBoards.BoardArchivedV1ToBoards do
  # Projects board_archived_v1 into boards.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [project: 3]

  @impl true
  def interested_in, do: ["board_archived_v1"]

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
      {"UPDATE boards SET status = status | 2, archived_at = ? WHERE board_id = ?",
       [data.at, data.board_id]}
    ]
  end
end
