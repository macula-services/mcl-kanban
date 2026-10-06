defmodule GuideCardLifecycle.CardState do
  # One card, one GitHub issue. Each event carries the card's status after it.
  @moduledoc false

  defstruct [
    :card_id,
    :issue_ref,
    :repo,
    :board_id,
    :title,
    :story,
    :kind,
    :rank,
    :rationale,
    :ranked_by,
    :lane,
    :lane_node_id,
    :holder,
    :holder_node_id,
    :queued_at,
    :claimed_at,
    tags: [],
    links: [],
    comment_count: 0,
    status: 0
  ]

  @type t :: %__MODULE__{}

  @spec new(String.t()) :: t()
  def new(card_id), do: %__MODULE__{card_id: card_id}

  @spec apply_event(t(), map()) :: t()
  def apply_event(state, %{data: data, event_type: type}),
    do: apply_event(state, Map.put(data, :event_type, type))

  def apply_event(state, %{event_type: type} = e), do: e |> fold(type, state) |> with_status(e)

  defp with_status(state, %{status: status}), do: %{state | status: status}
  defp with_status(state, _event), do: state

  defp fold(e, "card_queued_v1", s) do
    %{
      s
      | issue_ref: e.issue_ref,
        repo: e.repo,
        board_id: e.board_id,
        title: e.title,
        story: e.story,
        kind: e.kind,
        tags: e.tags,
        queued_at: e.at
    }
  end

  defp fold(e, "card_reworded_v1", s), do: %{s | title: e.title, story: e.story}
  defp fold(e, "card_reclassified_v1", s), do: %{s | kind: e.kind}
  defp fold(e, "card_tagged_v1", s), do: %{s | tags: s.tags ++ [e.tag]}
  defp fold(e, "card_untagged_v1", s), do: %{s | tags: List.delete(s.tags, e.tag)}

  defp fold(e, "card_prioritised_v1", s),
    do: %{s | rank: e.rank, rationale: e.rationale, ranked_by: e.by}

  defp fold(_e, "card_unpinned_v1", s), do: s
  defp fold(e, "card_reserved_v1", s), do: %{s | lane: e.lane, lane_node_id: e.lane_node_id}
  defp fold(_e, "card_reservation_lifted_v1", s), do: %{s | lane: nil, lane_node_id: nil}

  defp fold(e, "card_claimed_v1", s),
    do: %{s | holder: e.holder, holder_node_id: e.holder_node_id, claimed_at: e.at}

  defp fold(_e, "card_released_v1", s),
    do: %{s | holder: nil, holder_node_id: nil, claimed_at: nil}

  defp fold(e, "card_linked_v1", s),
    do: %{s | links: s.links ++ [%{to_card_id: e.to_card_id, link: e.link}]}

  defp fold(e, "card_unlinked_v1", s),
    do: %{s | links: List.delete(s.links, %{to_card_id: e.to_card_id, link: e.link})}

  defp fold(_e, "card_commented_v1", s), do: %{s | comment_count: s.comment_count + 1}
  defp fold(_e, _status_only, s), do: s
end
