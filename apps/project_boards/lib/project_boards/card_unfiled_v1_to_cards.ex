defmodule ProjectBoards.CardUnfiledV1ToCards do
  # Projects card_unfiled_v1 into cards: a loose card again, no package rank,
  # heading no package.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [card_update: 3, project: 3]

  @impl true
  def interested_in, do: ["card_unfiled_v1"]

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
        {"work_package", nil},
        {"package_rank", nil},
        {"package_card", 0}
      ])
    ]
end
