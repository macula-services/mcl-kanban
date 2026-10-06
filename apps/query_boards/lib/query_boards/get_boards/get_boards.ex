defmodule QueryBoards.GetBoards.GetBoards do
  # get_boards: every board, with how many cards sit in each column.
  @moduledoc false

  alias QueryBoards.ReadModel

  @spec get_boards() :: [map()]
  def get_boards do
    """
    SELECT b.board_id, b.repo, b.status, b.opened_at,
      (SELECT COUNT(*) FROM cards c WHERE c.board_id = b.board_id AND c.status & 30 = 0 AND c.status & 1 = 1),
      (SELECT COUNT(*) FROM cards c WHERE c.board_id = b.board_id AND c.status & 2 = 2 AND c.status & 28 = 0),
      (SELECT COUNT(*) FROM cards c WHERE c.board_id = b.board_id AND c.status & 4 = 4 AND c.status & 24 = 0),
      (SELECT COUNT(*) FROM cards c WHERE c.board_id = b.board_id AND c.status & 8 = 8)
    FROM boards b ORDER BY b.repo
    """
    |> ReadModel.q([])
    |> Enum.map(&board/1)
  end

  @doc false
  def board([id, repo, status, opened_at, queued, claimed, blocked, finished]) do
    %{
      board_id: id,
      repo: repo,
      archived: Bitwise.band(status, 2) |> Bitwise.bsr(1),
      opened_at: opened_at,
      counts: %{queued: queued, claimed: claimed, blocked: blocked, finished: finished}
    }
  end
end
