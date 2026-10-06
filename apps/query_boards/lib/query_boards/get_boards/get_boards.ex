defmodule QueryBoards.GetBoards.GetBoards do
  # get_boards: every board, with how many cards sit in each column. A
  # package's own card heads its package and sits in no column (#15), so an
  # idle agent never reads "queued: 1" for a card claim_next_card won't give.
  # Deferred cards (#17) are counted apart, for the same reason; a paused
  # repo's board says deferred 1.
  @moduledoc false

  alias QueryBoards.CardRows
  alias QueryBoards.ReadModel

  @spec get_boards() :: [map()]
  def get_boards do
    on_board = "c.board_id = b.board_id AND " <> CardRows.not_package_card()
    waiting = "c.status & 30 = 0 AND c.status & 1 = 1"

    """
    SELECT b.board_id, b.repo, b.status, b.opened_at,
      (SELECT COUNT(*) FROM cards c WHERE #{on_board} AND #{waiting} AND #{CardRows.not_deferred()}),
      (SELECT COUNT(*) FROM cards c WHERE #{on_board} AND c.status & 2 = 2 AND c.status & 28 = 0),
      (SELECT COUNT(*) FROM cards c WHERE #{on_board} AND c.status & 4 = 4 AND c.status & 24 = 0),
      (SELECT COUNT(*) FROM cards c WHERE #{on_board} AND c.status & 8 = 8),
      (SELECT COUNT(*) FROM cards c WHERE #{on_board} AND #{waiting} AND c.deferred = 1)
    FROM boards b ORDER BY b.repo
    """
    |> ReadModel.q([])
    |> Enum.map(&board/1)
  end

  @doc false
  def board([id, repo, status, opened_at, queued, claimed, blocked, finished, deferred]) do
    %{
      board_id: id,
      repo: repo,
      archived: Bitwise.band(status, 2) |> Bitwise.bsr(1),
      deferred: Bitwise.band(status, 4) |> Bitwise.bsr(2),
      opened_at: opened_at,
      counts: %{
        queued: queued,
        claimed: claimed,
        blocked: blocked,
        finished: finished,
        deferred: deferred
      }
    }
  end
end
