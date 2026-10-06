defmodule GuideCardLifecycle.BoardTest do
  # One board per repo: the supervisor (or the owner) opens and archives it.
  use ExUnit.Case, async: true

  import GuideCardLifecycle.TestCrew

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.ArchiveBoard.{ArchiveBoardV1, MaybeArchiveBoard}
  alias GuideCardLifecycle.BoardState
  alias GuideCardLifecycle.DeferBoard.{DeferBoardV1, MaybeDeferBoard}
  alias GuideCardLifecycle.IssueRef
  alias GuideCardLifecycle.OpenBoard.{MaybeOpenBoard, OpenBoardV1}
  alias GuideCardLifecycle.ResumeBoard.{MaybeResumeBoard, ResumeBoardV1}

  @repo "example-org/widget"

  defp opened do
    BoardState.apply_event(BoardState.new(IssueRef.board_id(@repo)), %{
      event_type: "board_opened_v1",
      board_id: IssueRef.board_id(@repo),
      repo: @repo
    })
  end

  test "the supervisor opens a board for a repo" do
    {:ok, cmd} = OpenBoardV1.new(%{repo: @repo, by: actor("ada")})
    assert cmd.board_id == IssueRef.board_id(@repo)

    assert {:ok, [%{event_type: "board_opened_v1", repo: @repo, by: "ada"}]} =
             MaybeOpenBoard.handle(BoardState.new(cmd.board_id), cmd)
  end

  test "the owner opens a board too; a plain agent may not" do
    {:ok, owner} = OpenBoardV1.new(%{repo: @repo, by: Actor.owner()})
    assert {:ok, [_]} = MaybeOpenBoard.handle(BoardState.new(owner.board_id), owner)

    {:ok, bob} = OpenBoardV1.new(%{repo: @repo, by: actor("bob")})
    assert {:error, :not_permitted} = MaybeOpenBoard.handle(BoardState.new(bob.board_id), bob)
  end

  test "a board is opened once" do
    {:ok, cmd} = OpenBoardV1.new(%{repo: @repo, by: actor("ada")})
    assert {:error, :already_open} = MaybeOpenBoard.handle(opened(), cmd)
  end

  test "a repo must read owner/repo" do
    for bad <- ["widget", "a/b/c", "", "owner/", "/repo", "own er/repo"] do
      assert {:error, :invalid_repo} = OpenBoardV1.new(%{repo: bad, by: actor("ada")}), bad
    end
  end

  test "archiving needs an open board, once, by the supervisor or the owner" do
    {:ok, cmd} = ArchiveBoardV1.new(%{repo: @repo, by: actor("ada")})
    assert {:error, :unknown_board} = MaybeArchiveBoard.handle(BoardState.new(cmd.board_id), cmd)
    {:ok, events} = MaybeArchiveBoard.handle(opened(), cmd)
    assert [%{event_type: "board_archived_v1"}] = events
    archived = Enum.reduce(events, opened(), &BoardState.apply_event(&2, &1))
    assert {:error, :already_archived} = MaybeArchiveBoard.handle(archived, cmd)

    {:ok, by_bob} = ArchiveBoardV1.new(%{repo: @repo, by: actor("bob")})
    assert {:error, :not_permitted} = MaybeArchiveBoard.handle(opened(), by_bob)
  end

  test "the owner or the prioritiser pauses a board's repo and resumes it (#17)" do
    {:ok, defer} = DeferBoardV1.new(%{repo: @repo, reason: "not now", by: actor("pia")})
    {:ok, events} = MaybeDeferBoard.handle(opened(), defer)
    assert [%{event_type: "board_deferred_v1", repo: @repo, reason: "not now"}] = events
    deferred = Enum.reduce(events, opened(), &BoardState.apply_event(&2, &1))
    assert BoardState.deferred?(deferred)
    assert {:error, :already_deferred} = MaybeDeferBoard.handle(deferred, defer)

    {:ok, resume} = ResumeBoardV1.new(%{repo: @repo, by: Actor.owner()})
    {:ok, events} = MaybeResumeBoard.handle(deferred, resume)
    resumed = Enum.reduce(events, deferred, &BoardState.apply_event(&2, &1))
    refute BoardState.deferred?(resumed)
    assert {:error, :not_deferred} = MaybeResumeBoard.handle(resumed, resume)

    {:ok, by_bob} = DeferBoardV1.new(%{repo: @repo, reason: "x", by: actor("bob")})
    assert {:error, :not_permitted} = MaybeDeferBoard.handle(opened(), by_bob)

    assert {:error, :unknown_board} =
             MaybeDeferBoard.handle(BoardState.new(defer.board_id), defer)
  end
end
