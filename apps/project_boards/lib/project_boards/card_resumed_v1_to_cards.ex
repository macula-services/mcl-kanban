defmodule ProjectBoards.CardResumedV1ToCards do
  # Projects card_resumed_v1 into cards: queued again, unless its package or board is still paused.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [card_update: 3, deferred: 2, project: 3]

  @impl true
  def interested_in, do: ["card_resumed_v1"]

  @impl true
  def replay_policy, do: :deliver

  @impl true
  def init(_config), do: {:ok, %{}}

  @impl true
  def handle_event(type, envelope, _metadata, state) do
    with {:ok, _} <- project(type, envelope, &statements/2), do: {:ok, state}
  end

  defp statements(data, version),
    do: [card_update(data, version, []), deferred("card_id = ?", [data.card_id])]
end
