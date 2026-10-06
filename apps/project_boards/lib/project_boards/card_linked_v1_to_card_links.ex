defmodule ProjectBoards.CardLinkedV1ToCardLinks do
  # Projects card_linked_v1 into card_links: stored on the source card; the query shows it both ways.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [card_update: 3, guarded: 4, project: 3]

  @impl true
  def interested_in, do: ["card_linked_v1"]

  @impl true
  def replay_policy, do: :deliver

  @impl true
  def init(_config), do: {:ok, %{}}

  @impl true
  def handle_event(type, envelope, _metadata, state) do
    with {:ok, _} <- project(type, envelope, &statements/2), do: {:ok, state}
  end

  defp statements(data, version) do
    [
      guarded(
        "INSERT OR IGNORE INTO card_links (card_id, to_card_id, link, linked_by, linked_at) SELECT ?, ?, ?, ?, ?",
        [data.card_id, data.to_card_id, data.link, data[:by], data.at],
        data,
        version
      ),
      card_update(data, version, [])
    ]
  end
end
