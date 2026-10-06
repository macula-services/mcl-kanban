defmodule QueryBoards.GetBoardByRepo.GetBoardByRepo do
  # get_board_by_repo: one board and its open and finished cards, in rank
  # order (unranked last, then oldest first). Withdrawn cards are left out.
  @moduledoc false

  alias QueryBoards.CardRows
  alias QueryBoards.GetBoards.GetBoards
  alias QueryBoards.ReadModel

  @spec get_board_by_repo(String.t()) ::
          {:ok, %{board: map(), cards: [map()]}} | {:error, :unknown_board}
  def get_board_by_repo(repo) when is_binary(repo) do
    "SELECT board_id, repo, status, opened_at, 0, 0, 0, 0, 0 FROM boards WHERE repo = ?"
    |> ReadModel.q([repo])
    |> found()
  end

  def get_board_by_repo(_), do: {:error, :unknown_board}

  defp found([row]) do
    board = GetBoards.board(row)

    cards =
      CardRows.cards(
        "WHERE c.board_id = ? AND c.status & 16 = 0 ORDER BY c.rank IS NULL, c.rank, c.queued_at",
        [board.board_id]
      )

    {:ok, %{board: Map.delete(board, :counts), cards: cards}}
  end

  defp found([]), do: {:error, :unknown_board}
end
