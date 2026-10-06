defmodule ProjectBoards.CardReleasedV1ToCards do
  # Projects card_released_v1 into cards: back in the queue, the reason kept as the note.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [card_update: 3, project: 3]

  @impl true
  def interested_in, do: ["card_released_v1"]

  @impl true
  def replay_policy, do: :deliver

  @impl true
  def init(_config), do: {:ok, %{}}

  @impl true
  def handle_event(type, envelope, _metadata, state) do
    with {:ok, _} <- project(type, envelope, &statements/2), do: {:ok, state}
  end

  defp statements(data, version),
    do: [
      card_update(data, version, [
        {"holder", nil},
        {"holder_node_id", nil},
        {"claimed_at", nil},
        {"note", data.reason}
      ])
    ]
end
