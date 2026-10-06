defmodule ProjectBoards.CardRewordedV1ToCards do
  # Projects card_reworded_v1 into cards.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [card_update: 3, project: 3]

  @impl true
  def interested_in, do: ["card_reworded_v1"]

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
        {"title", data.title},
        {"story_role", story(data, :role)},
        {"story_ask", story(data, :ask)},
        {"story_value", story(data, :value)}
      ])
    ]

  defp story(data, part), do: (data[:story] || %{})[part]
end
