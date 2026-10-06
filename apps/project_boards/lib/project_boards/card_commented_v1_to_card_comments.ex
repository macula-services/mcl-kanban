defmodule ProjectBoards.CardCommentedV1ToCardComments do
  # Projects card_commented_v1 into card_comments: append-only, keyed by comment id.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [card_update: 3, project: 3]

  @impl true
  def interested_in, do: ["card_commented_v1"]

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
      {"INSERT OR IGNORE INTO card_comments (comment_id, card_id, author, author_kind, text, at) VALUES (?, ?, ?, ?, ?, ?)",
       [data.comment_id, data.card_id, data[:by], data[:by_kind] || "agent", data.text, data.at]},
      {"UPDATE cards SET comment_count = (SELECT COUNT(*) FROM card_comments WHERE card_id = ?) WHERE card_id = ?",
       [data.card_id, data.card_id]},
      card_update(data, version, [])
    ]
  end
end
