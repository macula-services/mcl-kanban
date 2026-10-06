defmodule ProjectBoards.CardDeferredV1ToCards do
  # Projects card_deferred_v1 into cards: deferred, unranked, the reason as its note.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [card_update: 3, deferred: 2, project: 3]

  @impl true
  def interested_in, do: ["card_deferred_v1"]

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
        {"rank", nil},
        {"rationale", nil},
        {"ranked_by", nil},
        {"ranked_at", nil},
        {"note", data.reason}
      ]),
      deferred("card_id = ?", [data.card_id])
    ]
end
