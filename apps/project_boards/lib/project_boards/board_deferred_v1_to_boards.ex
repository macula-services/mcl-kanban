defmodule ProjectBoards.BoardDeferredV1ToBoards do
  # Projects board_deferred_v1 into boards and its cards: the repo is paused, so every card on its board is deferred.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [deferred: 2, project: 3]

  @impl true
  def interested_in, do: ["board_deferred_v1"]

  @impl true
  def replay_policy, do: :deliver

  @impl true
  def init(_config), do: {:ok, %{}}

  @impl true
  def handle_event(type, envelope, _metadata, state) do
    with {:ok, _} <- project(type, envelope, &statements/2), do: {:ok, state}
  end

  defp statements(data, _version),
    do: [
      {"UPDATE boards SET status = status | 4 WHERE board_id = ?", [data.board_id]},
      deferred("board_id = ?", [data.board_id])
    ]
end
