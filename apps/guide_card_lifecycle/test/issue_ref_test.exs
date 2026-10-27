defmodule GuideCardLifecycle.IssueRefTest do
  # A card IS a GitHub issue on the board: its id is derived from the issue
  # reference, so a second card for the same issue lands on the same stream.
  use ExUnit.Case, async: true

  alias GuideCardLifecycle.CardKind
  alias GuideCardLifecycle.IssueRef

  test "an issue reference reads owner/repo#number" do
    assert {:ok, %{repo: "example-org/widget", number: 12, issue_ref: "example-org/widget#12"}} =
             IssueRef.parse("example-org/widget#12")

    for bad <- ["widget#12", "example-org/widget", "example-org/widget#0", "a/b#x", "a/b#-1", ""] do
      assert {:error, :invalid_issue_ref} = IssueRef.parse(bad), bad
    end
  end

  test "a reference or repo with a trailing newline is refused, not read as one (#40)" do
    # `$` matches BEFORE a final newline: a pasted line ending parsed, and its
    # stream id was derived from the newline-carrying text, so the same issue
    # had a second card id.
    assert {:error, :invalid_issue_ref} = IssueRef.parse("example-org/widget#12\n")
    assert {:error, :invalid_repo} = IssueRef.repo("example-org/widget\n")
  end

  test "the card and board ids are stream ids reckon-db accepts, derived, stable" do
    card = IssueRef.card_id("example-org/widget#12")
    board = IssueRef.board_id("example-org/widget")

    assert :ok = :reckon_gater_stream_id.validate(card)
    assert :ok = :reckon_gater_stream_id.validate(board)
    assert card == IssueRef.card_id("example-org/widget#12")
    assert card != IssueRef.card_id("example-org/widget#13")
    assert "card-" <> _ = card
    assert "board-" <> _ = board
  end

  test "the issue's url on GitHub" do
    assert IssueRef.url("example-org/widget#12") ==
             "https://github.com/example-org/widget/issues/12"
  end

  test "kind gives the colour, Jira's: bug red, slice green, ui blue" do
    assert CardKind.kinds() == ["bug", "slice", "ui"]
    assert CardKind.colour("bug") == "#e5493a"
    assert CardKind.colour("slice") == "#63ba3c"
    assert CardKind.colour("ui") == "#4bade8"
  end
end
