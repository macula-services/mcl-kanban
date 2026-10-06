defmodule ProjectBoards.CardUnlinkedV1ToCardLinks do
  # Projects card_unlinked_v1 into card_links.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [card_update: 3, project: 3]

  @impl true
  def interested_in, do: ["card_unlinked_v1"]

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
      {"DELETE FROM card_links WHERE card_id = ? AND to_card_id = ? AND link = ? AND (SELECT version FROM cards WHERE card_id = ?) < ?",
       [data.card_id, data.to_card_id, data.link, data.card_id, version]},
      card_update(data, version, [])
    ]
  end
end
