defmodule ProjectBoards.CardPrioritisedV1ToCards do
  # Projects card_prioritised_v1 into cards: the rank, why, and who ranked it (an owner rank is recorded as the owner).
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [card_update: 3, project: 3]

  @impl true
  def interested_in, do: ["card_prioritised_v1"]

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
        {"rank", data.rank},
        {"rationale", data.rationale},
        {"ranked_by", data[:by]}
      ])
    ]
end
