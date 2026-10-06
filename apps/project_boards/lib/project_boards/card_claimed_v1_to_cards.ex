defmodule ProjectBoards.CardClaimedV1ToCards do
  # Projects card_claimed_v1 into cards.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [card_update: 3, project: 3]

  @impl true
  def interested_in, do: ["card_claimed_v1"]

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
        {"holder", data.holder},
        {"holder_node_id", data.holder_node_id},
        {"claimed_at", data.at}
      ])
    ]
end
