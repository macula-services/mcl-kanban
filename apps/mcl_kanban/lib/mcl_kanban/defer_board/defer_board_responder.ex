defmodule MclKanban.DeferBoard.DeferBoardResponder do
  # mcl-kanban/defer_board: repo, reason. The prioritiser or the owner pauses a repo: none of its
  # cards is handed out until resumed; no card is marked blocked (#17).
  # Replies the board.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.DeferBoard.{MaybeDeferBoard, DeferBoardV1}
  alias MclKanban.Wire
  alias QueryBoards.GetBoards.GetBoards

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, cmd} <-
             DeferBoardV1.new(%{
               repo: Wire.arg(payload, :repo),
               reason: Wire.arg(payload, :reason),
               by: by
             }),
           {:ok, _version, _events} <- MaybeDeferBoard.dispatch(cmd),
           :ok <- GetBoards.await_deferred(cmd.board_id, 1),
           do: {:ok, %{board: %{board_id: cmd.board_id, repo: cmd.repo, deferred: 1}}}

    {:reply, Wire.reply(reply), state}
  end
end
