defmodule ProjectBoards.ProjectionsTest do
  # Each event lands in the read model through its own {event}_to_{table}
  # projection, as evoq delivers it (an envelope with data and the stream
  # version), and announces the write on the pubsub seam.
  use ExUnit.Case, async: false

  alias ProjectBoards.BoardsChanged
  alias ProjectBoards.ReadModel

  @projections ProjectBoards.Application.projections()

  defp deliver(event, version) do
    type = event.event_type
    [module] = Enum.filter(@projections, &(type in &1.interested_in()))

    envelope = %{
      event_type: type,
      event_id: "evt-#{System.unique_integer([:positive])}",
      version: version,
      data: event
    }

    assert {:ok, _} = module.handle_event(type, envelope, %{version: version}, %{})
  end

  defp uniq, do: Integer.to_string(System.unique_integer([:positive]))

  test "every event the departments emit has exactly one projection" do
    types = Enum.flat_map(@projections, & &1.interested_in())
    assert types == Enum.uniq(types)

    for type <- ~w(board_opened_v1 board_archived_v1 agent_enlisted_v1 agent_discharged_v1
                   supervisor_appointed_v1 prioritiser_appointed_v1 card_queued_v1
                   card_reworded_v1 card_reclassified_v1 card_tagged_v1 card_untagged_v1
                   card_prioritised_v1 card_unpinned_v1 card_reserved_v1
                   card_reservation_lifted_v1 card_claimed_v1 card_released_v1
                   card_blocked_v1 card_unblocked_v1 card_finished_v1 card_withdrawn_v1
                   card_linked_v1 card_unlinked_v1 card_commented_v1) do
      assert type in types, type
    end
  end

  test "every projection replays: its writes are idempotent" do
    for projection <- @projections do
      assert projection.replay_policy() == :deliver, inspect(projection)
    end
  end

  test "a queued card is a row on its board, unranked, with its tags" do
    :ok = Phoenix.PubSub.subscribe(MclKanbanWeb.PubSub, BoardsChanged.topic())
    id = "card-" <> String.duplicate("a", 26) <> String.pad_leading(uniq(), 6, "0")

    deliver(
      %{
        event_type: "card_queued_v1",
        card_id: id,
        issue_ref: "example-org/widget#1",
        repo: "example-org/widget",
        board_id: "board-" <> String.duplicate("b", 32),
        title: "First",
        story: %{role: "agent", ask: "x", value: "y"},
        kind: "bug",
        tags: ["a", "b"],
        status: 1,
        by: "bob",
        at: 100
      },
      0
    )

    assert [[^id, "First", "bug", 1, :undefined, 0, 100]] =
             ReadModel.q(
               "SELECT card_id, title, kind, status, rank, version, queued_at FROM cards WHERE card_id = ?",
               [id]
             )

    assert [["a"], ["b"]] =
             ReadModel.q("SELECT tag FROM card_tags WHERE card_id = ? ORDER BY tag", [id])

    assert_receive {:boards_changed, %{card_id: ^id, event_type: "card_queued_v1"}}

    deliver(%{event_type: "card_claimed_v1", card_id: id, holder: "bob", holder_node_id: "ab", status: 2, at: 200}, 1)
    deliver(%{event_type: "card_tagged_v1", card_id: id, tag: "c", status: 2, at: 201}, 2)
    deliver(%{event_type: "card_untagged_v1", card_id: id, tag: "a", status: 2, at: 202}, 3)
    # Replayed: the same event twice is the same write twice.
    deliver(%{event_type: "card_tagged_v1", card_id: id, tag: "c", status: 2, at: 201}, 2)

    assert [["bob", "ab", 2, 200, 3]] =
             ReadModel.q(
               "SELECT holder, holder_node_id, status, claimed_at, version FROM cards WHERE card_id = ?",
               [id]
             )

    assert [["b"], ["c"]] =
             ReadModel.q("SELECT tag FROM card_tags WHERE card_id = ? ORDER BY tag", [id])
  end

  test "links and comments have their own tables; the version only moves forward" do
    id = "card-" <> String.duplicate("c", 26) <> String.pad_leading(uniq(), 6, "0")
    to = "card-" <> String.duplicate("d", 32)

    deliver(
      %{
        event_type: "card_queued_v1",
        card_id: id,
        issue_ref: "example-org/widget#2",
        repo: "example-org/widget",
        board_id: "board-" <> String.duplicate("b", 32),
        title: "Second",
        story: nil,
        kind: "ui",
        tags: [],
        status: 1,
        by: "bob",
        at: 100
      },
      0
    )

    deliver(%{event_type: "card_linked_v1", card_id: id, to_card_id: to, link: "blocks", status: 1, at: 1}, 1)

    deliver(
      %{event_type: "card_commented_v1", card_id: id, comment_id: "c1" <> uniq(), text: "hi", by: "cyd", by_kind: "agent", status: 1, at: 2},
      2
    )

    # A late redelivery of version 1 does not move the row back.
    deliver(%{event_type: "card_linked_v1", card_id: id, to_card_id: to, link: "blocks", status: 1, at: 1}, 1)

    assert [[^id, ^to, "blocks"]] =
             ReadModel.q("SELECT card_id, to_card_id, link FROM card_links WHERE card_id = ?", [id])

    assert [["hi", "cyd"]] = ReadModel.q("SELECT text, author FROM card_comments WHERE card_id = ?", [id])
    assert [[2, 1]] = ReadModel.q("SELECT version, comment_count FROM cards WHERE card_id = ?", [id])

    deliver(%{event_type: "card_unlinked_v1", card_id: id, to_card_id: to, link: "blocks", status: 1, at: 3}, 3)
    assert [] = ReadModel.q("SELECT 1 FROM card_links WHERE card_id = ?", [id])
  end

  test "the crew table follows enlistment, appointments and discharge" do
    name = "agent" <> uniq()
    node = String.pad_leading(uniq(), 64, "e")

    deliver(%{event_type: "agent_enlisted_v1", node_id: node, name: name, at: 1}, 0)
    deliver(%{event_type: "prioritiser_appointed_v1", node_id: node, name: name, at: 2}, 1)

    assert [[^name, "agent,prioritiser"]] =
             ReadModel.q("SELECT name, roles FROM crew WHERE node_id = ?", [node])

    deliver(%{event_type: "agent_discharged_v1", node_id: node, name: name, at: 3}, 2)
    assert [] = ReadModel.q("SELECT 1 FROM crew WHERE node_id = ?", [node])
  end

  test "a board row is opened and archived" do
    id = "board-" <> String.pad_leading(uniq(), 32, "f")
    deliver(%{event_type: "board_opened_v1", board_id: id, repo: "example-org/r" <> uniq(), at: 1}, 0)
    assert [[1]] = ReadModel.q("SELECT status FROM boards WHERE board_id = ?", [id])
    deliver(%{event_type: "board_archived_v1", board_id: id, at: 2}, 1)
    assert [[3]] = ReadModel.q("SELECT status FROM boards WHERE board_id = ?", [id])
  end
end
