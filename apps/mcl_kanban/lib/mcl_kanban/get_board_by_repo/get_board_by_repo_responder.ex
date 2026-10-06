defmodule MclKanban.GetBoardByRepo.GetBoardByRepoResponder do
  # mcl-kanban/get_board_by_repo: repo (owner/repo). The board and its cards in rank order. Enlisted agents only.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias MclKanban.Wire
  alias QueryBoards.GetBoardByRepo.GetBoardByRepo

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply = with {:ok, by} <- Actor.of_caller(payload), do: read(by, payload)
    {:reply, Wire.reply(reply), state}
  end

  defp read(_by, payload) do
    with {:ok, %{board: board, cards: cards}} <-
           GetBoardByRepo.get_board_by_repo(Wire.arg(payload, :repo)),
         do: {:ok, %{board: board, cards: Enum.map(cards, &Wire.card/1)}}
  end
end
