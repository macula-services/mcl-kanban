defmodule ProjectBoards.CardTaggedV1ToCardTags do
  # Projects card_tagged_v1 into card_tags.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [card_update: 3, guarded: 4, project: 3]

  @impl true
  def interested_in, do: ["card_tagged_v1"]

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
        "INSERT OR IGNORE INTO card_tags (card_id, tag) SELECT ?, ?",
        [data.card_id, data.tag],
        data,
        version
      ),
      card_update(data, version, [])
    ]
  end
end
