defmodule ProjectBoards.CardQueuedV1ToCards do
  # Projects card_queued_v1 into cards and card_tags: a new row, unranked.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [deferred: 2, project: 3]

  @impl true
  def interested_in, do: ["card_queued_v1"]

  @impl true
  def replay_policy, do: :deliver

  @impl true
  def init(_config), do: {:ok, %{}}

  @impl true
  def handle_event(type, envelope, _metadata, state) do
    with {:ok, _} <- project(type, envelope, &statements/2), do: {:ok, state}
  end

  defp statements(data, version) do
    story = data[:story] || %{}

    [
      {"INSERT OR IGNORE INTO cards (card_id, issue_ref, repo, board_id, title, story_role, story_ask, story_value, kind, status, queued_by, queued_at, changed_at, version) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
       [
         data.card_id,
         data.issue_ref,
         data.repo,
         data.board_id,
         data.title,
         story[:role],
         story[:ask],
         story[:value],
         data.kind,
         data.status,
         data[:by],
         data.at,
         data.at,
         version
       ]}
    ] ++
      Enum.map(
        data.tags,
        &{"INSERT OR IGNORE INTO card_tags (card_id, tag) VALUES (?, ?)", [data.card_id, &1]}
      ) ++ [deferred("card_id = ?", [data.card_id])]
  end
end
