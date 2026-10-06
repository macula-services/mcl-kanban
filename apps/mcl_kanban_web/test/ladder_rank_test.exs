defmodule MclKanbanWeb.LadderRankTest do
  # Where a dragged card lands: one rank between its new neighbours, so a
  # move is one owner prioritise_card and no other card moves. Equal ranks
  # keep the order they were ranked in, so the moved card (ranked last) sits
  # after a neighbour of the same rank.
  use ExUnit.Case, async: true

  alias MclKanbanWeb.LadderRank

  @ranks %{"a" => 2, "b" => 6, "c" => 3, "z" => 0, "u" => nil}

  test "between two ranks with room: the middle" do
    assert {:ok, 4} = LadderRank.place(@ranks, "a", "b")
  end

  test "between two ranks with no room: the rank above, and the tie puts it after" do
    assert {:ok, 2} = LadderRank.place(@ranks, "a", "c")
  end

  test "after the last card: one below it" do
    assert {:ok, 7} = LadderRank.place(@ranks, "b", nil)
  end

  test "before the first card: one above it, never below 0" do
    assert {:ok, 5} = LadderRank.place(@ranks, nil, "b")
    assert {:ok, 0} = LadderRank.place(@ranks, nil, "z")
  end

  test "into an empty group, or above an unranked card at the top: rank 0" do
    assert {:ok, 0} = LadderRank.place(@ranks, nil, nil)
    assert {:ok, 0} = LadderRank.place(@ranks, nil, "u")
  end

  test "after a ranked card, above an unranked one: one below the ranked card" do
    assert {:ok, 3} = LadderRank.place(@ranks, "a", "u")
  end

  test "below an unranked card is refused: rank that card first" do
    assert {:error, :unranked_target} = LadderRank.place(@ranks, "u", nil)
  end

  test "a neighbour the ladder does not hold is refused" do
    assert {:error, :unknown_card} = LadderRank.place(@ranks, "gone", nil)
    assert {:error, :unknown_card} = LadderRank.place(@ranks, nil, "gone")
  end
end
