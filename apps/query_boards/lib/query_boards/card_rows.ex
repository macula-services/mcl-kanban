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
             "c.package_rank, c.package_card"

  @doc "The order of the ladder inside a group: rank (unranked last), then when ranked, then age."
  def ladder_order, do: "c.rank IS NULL, c.rank, c.ranked_at, c.queued_at"

  @doc """
  The condition a query adds to leave out every package's own card (#15): it
  heads its package and is never waiting work.
  """
  def not_package_card, do: "c.package_card = 0"

  @doc "SELECT <card columns> FROM cards c <rest>."
  def select(rest), do: "SELECT #{@columns} FROM cards c " <> rest

  @doc """
  The cards the select matches, with their tags and links. Three queries
  read the tags and links of every card at once, however many cards there
  are: one query per card each made an owner UI reload cost hundreds.
  """
  @spec cards(String.t(), list()) :: [map()]
  def cards(rest, args) do
    rows = select(rest) |> ReadModel.q(args)
    related = related(Enum.map(rows, &hd/1))
    Enum.map(rows, &card(&1, related))
  end

  defp related([]), do: %{tags: %{}, links: %{}, linked_from: %{}}

  defp related(ids) do
    marks = Enum.map_join(ids, ", ", fn _ -> "?" end)

    %{
      tags:
        grouped(
          "SELECT card_id, tag FROM card_tags WHERE card_id IN (#{marks}) ORDER BY tag",
          ids,
          fn [_id, tag] -> tag end
        ),
      links:
        grouped(
          "SELECT card_id, to_card_id, link FROM card_links WHERE card_id IN (#{marks}) " <>
            "ORDER BY linked_at",
          ids,
          fn [_id, to, link] -> %{to_card_id: to, link: link} end
        ),
      linked_from:
        grouped(
          "SELECT to_card_id, card_id, link FROM card_links WHERE to_card_id IN (#{marks}) " <>
            "ORDER BY linked_at",
          ids,
          fn [_id, from, link] -> %{from_card_id: from, link: link} end
        )
    }
  end

  # Rows keyed by their first column, each group in the order the query read it.
  defp grouped(sql, ids, value), do: sql |> ReadModel.q(ids) |> Enum.group_by(&hd/1, value)

  defp card(
         [
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
           package_rank,
           package_card
         ],
         related
       ) do
    %{
      card_id: id,
      issue_ref: ref,
      board: repo,
      board_id: board_id,
      title: title,
      story: story(role, ask, value),
      kind: kind,
      colour: CardKind.colour(kind),
      tags: Map.get(related.tags, id, []),
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
      links: Map.get(related.links, id, []),
      linked_from: Map.get(related.linked_from, id, []),
      comment_count: comment_count,
      queued_by: queued_by,
      queued_at: queued_at,
      claimed_at: claimed_at,
      changed_at: changed_at,
      version: version,
      ranked_at: ranked_at,
      work_package: work_package,
      package_rank: package_rank,
      package_card: package_card
    }
  end

  defp story(nil, nil, nil), do: nil
  defp story(role, ask, value), do: %{role: role, ask: ask, value: value}

  defp pinned(true), do: 1
  defp pinned(false), do: 0

  @doc "A card's comment thread, oldest first."
  def comments(id) do
    "SELECT comment_id, author, author_kind, text, at FROM card_comments WHERE card_id = ? ORDER BY at, comment_id"
    |> ReadModel.q([id])
    |> Enum.map(fn [cid, author, kind, text, at] ->
      %{comment_id: cid, author: author, author_kind: kind, text: text, at: at}
    end)
  end
end
