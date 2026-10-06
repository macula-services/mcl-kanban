defmodule QueryBoards.QueriesTest do
  # The query desks over the read model the projections write. The rows are
  # written through the real projections, so each SELECT is pinned to the
  # schema project_boards owns. Every test uses its own repo and agents: the
  # whole suite shares one sqlite file.
  use ExUnit.Case, async: false

  alias QueryBoards.GetBoardByRepo.GetBoardByRepo
  alias QueryBoards.GetBoards.GetBoards
  alias QueryBoards.GetCardById.GetCardById
  alias QueryBoards.GetCardsByHolder.GetCardsByHolder
  alias QueryBoards.GetCrew.GetCrew
  alias QueryBoards.GetLadder.GetLadder
  alias QueryBoards.GetNextCardForAgent.GetNextCardForAgent
  alias QueryBoards.GetRankedCards.GetRankedCards

  @projections ProjectBoards.Application.projections()

  # The synthetic rows written here have no stream behind them. The umbrella
  # runs every app's tests in one VM over one read model, so they go when
  # this module is done, before the service's tests claim from the queue.
  setup_all do
    on_exit(fn ->
      :ok =
        ProjectBoards.ReadModel.write(
          for t <- ~w(cards card_tags card_links card_comments boards crew packages),
              do: {"DELETE FROM " <> t, []}
        )
    end)
  end

  defp deliver(event, version) do
    [module] = Enum.filter(@projections, &(event.event_type in &1.interested_in()))
    envelope = %{event_type: event.event_type, version: version, data: event}
    {:ok, _} = module.handle_event(event.event_type, envelope, %{version: version}, %{})
    :ok
  end

  defp uniq, do: Integer.to_string(System.unique_integer([:positive]))
  defp hex32(seed), do: :crypto.hash(:md5, seed) |> Base.encode16(case: :lower)

  defp board(repo) do
    id = "board-" <> hex32(repo)
    deliver(%{event_type: "board_opened_v1", board_id: id, repo: repo, at: 1}, 0)
    id
  end

  defp card(repo, board_id, n, fields \\ %{}) do
    ref = "#{repo}##{n}"
    id = "card-" <> hex32(ref)

    deliver(
      Map.merge(
        %{
          event_type: "card_queued_v1",
          card_id: id,
          issue_ref: ref,
          repo: repo,
          board_id: board_id,
          title: "Card #{n}",
          story: nil,
          kind: "slice",
          tags: [],
          status: 1,
          by: "bob",
          at: n
        },
        fields
      ),
      0
    )

    id
  end

  defp rank(id, rank, version, pinned \\ 0) do
    deliver(
      %{
        event_type: "card_prioritised_v1",
        card_id: id,
        rank: rank,
        rationale: "because",
        by: "pia",
        status: 1 + pinned * 32,
        at: 5
      },
      version
    )
  end

  test "next card for an agent: its lane first, then unreserved, by rank, then age; never claimed or blocked" do
    repo = "example-org/next" <> uniq()
    b = board(repo)
    me = String.duplicate("1", 63) <> "a"
    other = String.duplicate("2", 63) <> "a"

    old_unranked = card(repo, b, 1)
    ranked_low = card(repo, b, 2)
    ranked_high = card(repo, b, 3)
    mine = card(repo, b, 4)
    theirs = card(repo, b, 5)
    claimed = card(repo, b, 6)
    blocked = card(repo, b, 7)

    rank(ranked_low, 20, 1)
    rank(ranked_high, 10, 1)
    rank(mine, 90, 1)
    rank(claimed, 1, 1)
    rank(blocked, 1, 1)

    deliver(
      %{
        event_type: "card_reserved_v1",
        card_id: mine,
        lane: "me",
        lane_node_id: me,
        status: 1,
        at: 6
      },
      2
    )

    deliver(
      %{
        event_type: "card_reserved_v1",
        card_id: theirs,
        lane: "them",
        lane_node_id: other,
        status: 1,
        at: 6
      },
      1
    )

    deliver(
      %{
        event_type: "card_claimed_v1",
        card_id: claimed,
        holder: "x",
        holder_node_id: other,
        status: 2,
        at: 7
      },
      2
    )

    deliver(%{event_type: "card_blocked_v1", card_id: blocked, reason: "r", status: 5, at: 7}, 2)

    ids =
      me
      |> GetNextCardForAgent.get_next_card_for_agent(50)
      |> Enum.map(& &1.card_id)
      |> Enum.filter(
        &(&1 in [old_unranked, ranked_low, ranked_high, mine, theirs, claimed, blocked])
      )

    assert ids == [mine, ranked_high, ranked_low, old_unranked]
  end

  test "a card by id carries both directions of its links, its tags and comments" do
    repo = "example-org/links" <> uniq()
    b = board(repo)
    a = card(repo, b, 1, %{tags: ["x"], story: %{role: "r", ask: "a", value: "v"}})
    c = card(repo, b, 2, %{kind: "bug"})

    deliver(
      %{
        event_type: "card_linked_v1",
        card_id: a,
        to_card_id: c,
        link: "blocks",
        status: 1,
        at: 2
      },
      1
    )

    deliver(
      %{
        event_type: "card_commented_v1",
        card_id: c,
        comment_id: hex32("cm" <> uniq()),
        text: "hello",
        by: "cyd",
        by_kind: "agent",
        status: 1,
        at: 3
      },
      1
    )

    assert {:ok, card_a} = GetCardById.get_card_by_id(a)
    assert card_a.links == [%{to_card_id: c, link: "blocks"}]
    assert card_a.linked_from == []
    assert card_a.tags == ["x"]
    assert card_a.story == %{role: "r", ask: "a", value: "v"}
    assert card_a.board == repo
    assert card_a.state == "queued"
    assert card_a.colour == "#63ba3c"
    assert card_a.pinned == 0

    assert {:ok, card_c} = GetCardById.get_card_by_id(c)
    assert card_c.linked_from == [%{from_card_id: a, link: "blocks"}]
    assert card_c.colour == "#e5493a"
    assert card_c.comment_count == 1
    assert [%{text: "hello", author: "cyd"}] = card_c.comments

    assert {:error, :unknown_card} = GetCardById.get_card_by_id("card-" <> hex32("none"))
  end

  test "waiting for a version returns once the read model has it, and times out otherwise" do
    repo = "example-org/wait" <> uniq()
    id = card(repo, board(repo), 1)
    assert {:ok, %{card_id: ^id}} = GetCardById.get_card_by_id(id, 0)
    assert {:error, :read_model_behind} = GetCardById.get_card_by_id(id, 5, 100)
  end

  test "boards, a board's cards, a holder's cards, the global rank order, the crew" do
    repo = "example-org/all" <> uniq()
    b = board(repo)
    one = card(repo, b, 1)
    two = card(repo, b, 2)
    rank(two, 0, 1, 1)
    node = hex32("holder" <> uniq()) <> hex32("x")

    deliver(
      %{
        event_type: "card_claimed_v1",
        card_id: one,
        holder: "bob",
        holder_node_id: node,
        status: 2,
        at: 9
      },
      1
    )

    assert Enum.any?(GetBoards.get_boards(), &(&1.repo == repo and &1.board_id == b))
    assert {:ok, %{board: %{repo: ^repo}, cards: cards}} = GetBoardByRepo.get_board_by_repo(repo)
    assert Enum.sort(Enum.map(cards, & &1.card_id)) == Enum.sort([one, two])

    assert {:error, :unknown_board} =
             GetBoardByRepo.get_board_by_repo("example-org/none" <> uniq())

    assert [%{card_id: ^one, holder: "bob"}] = GetCardsByHolder.get_cards_by_holder(node)

    ranked = GetRankedCards.get_ranked_cards() |> Enum.map(& &1.card_id)

    assert Enum.find_index(ranked, &(&1 == two)) < Enum.find_index(ranked, &(&1 == one)) or
             one not in ranked

    name = "q" <> uniq()
    deliver(%{event_type: "agent_enlisted_v1", node_id: node, name: name, at: 1}, 0)
    assert Enum.any?(GetCrew.get_crew(), &(&1.name == name and &1.roles == ["agent"]))
  end

  defp package(ref, rank, version \\ 1, pinned \\ 0) do
    id = "package-" <> hex32(ref)

    deliver(
      %{
        event_type: "package_opened_v1",
        package_id: id,
        issue_ref: ref,
        title: "P " <> ref,
        status: 1,
        by: "ada",
        at: 1
      },
      0
    )

    ranked(id, ref, rank, version, pinned)
    ref
  end

  defp ranked(_id, _ref, nil, _version, _pinned), do: :ok

  defp ranked(id, ref, rank, version, pinned) do
    deliver(
      %{
        event_type: "package_prioritised_v1",
        package_id: id,
        issue_ref: ref,
        rank: rank,
        rationale: "why " <> ref,
        status: 1 + pinned * 2,
        by: "pia",
        at: 2
      },
      version
    )
  end

  defp file(card_id, ref, version),
    do:
      deliver(
        %{
          event_type: "card_filed_v1",
          card_id: card_id,
          work_package: ref,
          status: 1,
          by: "ada",
          at: 3
        },
        version
      )

  test "the ladder: packages by rank, unranked last, each with its cards by rank; loose cards apart; withdrawn gone" do
    repo = "example-org/ladder" <> uniq()
    b = board(repo)
    second = package(repo <> "#100", 2)
    first = package(repo <> "#101", 1, 1, 1)
    unranked = package(repo <> "#102", nil)

    a = card(repo, b, 1)
    c = card(repo, b, 2)
    d = card(repo, b, 3)
    loose = card(repo, b, 4)
    gone = card(repo, b, 5)

    rank(a, 5, 1)
    rank(c, 3, 1)
    file(a, first, 2)
    file(c, first, 2)
    file(d, second, 1)
    deliver(%{event_type: "card_withdrawn_v1", card_id: gone, reason: "no", status: 16, at: 9}, 1)

    ladder = GetLadder.get_ladder()
    mine = Enum.filter(ladder.packages, &String.starts_with?(&1.issue_ref, repo <> "#"))
    assert Enum.map(mine, & &1.issue_ref) == [first, second, unranked]

    [p1, p2, p3] = mine
    assert p1.rank == 1 and p1.pinned == 1 and p1.rationale == "why " <> first
    assert Enum.map(p1.cards, & &1.card_id) == [c, a]
    assert Enum.map(p2.cards, & &1.card_id) == [d]
    assert p3.cards == [] and p3.rank == nil
    assert p1.repos == [repo]

    loose_ids = Enum.map(ladder.loose, & &1.card_id)
    assert loose in loose_ids
    refute gone in loose_ids
    assert hd(p1.cards).work_package == first
    assert hd(p1.cards).package_rank == 1
  end

  test "equal ranks keep the order they were ranked in" do
    repo = "example-org/ties" <> uniq()
    b = board(repo)
    older = card(repo, b, 1)
    newer = card(repo, b, 2)

    deliver(
      %{
        event_type: "card_prioritised_v1",
        card_id: newer,
        rank: 4,
        rationale: "",
        by: "owner",
        status: 33,
        at: 50
      },
      1
    )

    deliver(
      %{
        event_type: "card_prioritised_v1",
        card_id: older,
        rank: 4,
        rationale: "",
        by: "owner",
        status: 33,
        at: 60
      },
      1
    )

    ids =
      GetLadder.get_ladder().loose
      |> Enum.map(& &1.card_id)
      |> Enum.filter(&(&1 in [older, newer]))

    assert ids == [newer, older]
  end

  test "the next card follows the ladder: package rank first, then card rank; loose cards after every package" do
    repo = "example-org/order" <> uniq()
    b = board(repo)
    me = hex32("order" <> uniq()) <> hex32("me")
    top = package(repo <> "#200", 1)
    low = package(repo <> "#201", 2)

    in_low = card(repo, b, 1)
    in_top = card(repo, b, 2)
    loose = card(repo, b, 3)
    rank(in_low, 0, 1)
    rank(in_top, 50, 1)
    rank(loose, 0, 1)
    file(in_low, low, 2)
    file(in_top, top, 2)

    ids =
      me
      |> GetNextCardForAgent.get_next_card_for_agent(500)
      |> Enum.map(& &1.card_id)
      |> Enum.filter(&(&1 in [in_low, in_top, loose]))

    assert ids == [in_top, in_low, loose]
  end

  test "the crew carries what each agent holds and the next card in its lane" do
    repo = "example-org/crew" <> uniq()
    b = board(repo)
    node = hex32("crew" <> uniq()) <> hex32("n")
    name = "c" <> uniq()
    deliver(%{event_type: "agent_enlisted_v1", node_id: node, name: name, at: 1}, 0)

    held = card(repo, b, 1)
    stuck = card(repo, b, 2)
    next = card(repo, b, 3)

    deliver(
      %{
        event_type: "card_claimed_v1",
        card_id: held,
        holder: name,
        holder_node_id: node,
        status: 2,
        at: 4
      },
      1
    )

    deliver(
      %{
        event_type: "card_claimed_v1",
        card_id: stuck,
        holder: name,
        holder_node_id: node,
        status: 2,
        at: 4
      },
      1
    )

    deliver(%{event_type: "card_blocked_v1", card_id: stuck, reason: "r", status: 6, at: 5}, 2)

    deliver(
      %{
        event_type: "card_reserved_v1",
        card_id: next,
        lane: name,
        lane_node_id: node,
        status: 1,
        at: 6
      },
      1
    )

    agent = Enum.find(GetCrew.get_crew(), &(&1.node_id == node))
    assert Enum.sort(Enum.map(agent.held, & &1.card_id)) == Enum.sort([held, stuck])
    assert agent.next.card_id == next
  end
end
