defmodule QueryBoards.CardRows do
  # How a card reads out of the read model, the same for every query: the
  # row, its tags, its links in both directions, and the derived words (state,
  # colour, pinned 0/1).
  @moduledoc false

  alias GuideCardLifecycle.CardKind
  alias GuideCardLifecycle.CardStatus
  alias QueryBoards.ReadModel

  @columns "c.card_id, c.issue_ref, c.repo, c.board_id, c.title, c.story_role, c.story_ask, " <>
             "c.story_value, c.kind, c.rank, c.rationale, c.ranked_by, c.lane, c.lane_node_id, " <>
             "c.holder, c.holder_node_id, c.status, c.comment_count, c.note, c.queued_by, " <>
             "c.queued_at, c.claimed_at, c.changed_at, c.version, c.ranked_at, c.work_package, " <>
             "c.package_rank"

  @doc "The order of the ladder inside a group: rank (unranked last), then when ranked, then age."
  def ladder_order, do: "c.rank IS NULL, c.rank, c.ranked_at, c.queued_at"

  @doc "SELECT <card columns> FROM cards c <rest>."
  def select(rest), do: "SELECT #{@columns} FROM cards c " <> rest

  @spec cards(String.t(), list()) :: [map()]
  def cards(rest, args), do: select(rest) |> ReadModel.q(args) |> Enum.map(&card/1)

  defp card([
         id,
         ref,
         repo,
         board_id,
         title,
         role,
         ask,
         value,
         kind,
         rank,
         rationale,
         ranked_by,
         lane,
         lane_node_id,
         holder,
         holder_node_id,
         status,
         comment_count,
         note,
         queued_by,
         queued_at,
         claimed_at,
         changed_at,
         version,
         ranked_at,
         work_package,
         package_rank
       ]) do
    %{
      card_id: id,
      issue_ref: ref,
      board: repo,
      board_id: board_id,
      title: title,
      story: story(role, ask, value),
      kind: kind,
      colour: CardKind.colour(kind),
      tags: tags(id),
      rank: rank,
      rationale: rationale,
      ranked_by: ranked_by,
      lane: lane,
      lane_node_id: lane_node_id,
      holder: holder,
      holder_node_id: holder_node_id,
      status: status,
      state: CardStatus.state_name(status),
      pinned: pinned(CardStatus.pinned?(status)),
      note: note,
      links: links(id),
      linked_from: linked_from(id),
      comment_count: comment_count,
      queued_by: queued_by,
      queued_at: queued_at,
      claimed_at: claimed_at,
      changed_at: changed_at,
      version: version,
      ranked_at: ranked_at,
      work_package: work_package,
      package_rank: package_rank
    }
  end

  defp story(nil, nil, nil), do: nil
  defp story(role, ask, value), do: %{role: role, ask: ask, value: value}

  defp pinned(true), do: 1
  defp pinned(false), do: 0

  defp tags(id),
    do:
      ReadModel.q("SELECT tag FROM card_tags WHERE card_id = ? ORDER BY tag", [id])
      |> Enum.map(&hd/1)

  defp links(id) do
    "SELECT to_card_id, link FROM card_links WHERE card_id = ? ORDER BY linked_at"
    |> ReadModel.q([id])
    |> Enum.map(fn [to, link] -> %{to_card_id: to, link: link} end)
  end

  defp linked_from(id) do
    "SELECT card_id, link FROM card_links WHERE to_card_id = ? ORDER BY linked_at"
    |> ReadModel.q([id])
    |> Enum.map(fn [from, link] -> %{from_card_id: from, link: link} end)
  end

  @doc "A card's comment thread, oldest first."
  def comments(id) do
    "SELECT comment_id, author, author_kind, text, at FROM card_comments WHERE card_id = ? ORDER BY at, comment_id"
    |> ReadModel.q([id])
    |> Enum.map(fn [cid, author, kind, text, at] ->
      %{comment_id: cid, author: author, author_kind: kind, text: text, at: at}
    end)
  end
end
