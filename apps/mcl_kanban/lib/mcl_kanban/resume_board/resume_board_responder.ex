defmodule MclKanban.ResumeBoard.ResumeBoardResponder do
  # mcl-kanban/resume_board: repo. The prioritiser or the owner resumes a paused repo (#17).
  # Replies the board.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.ResumeBoard.{MaybeResumeBoard, ResumeBoardV1}
  alias MclKanban.Wire
  alias QueryBoards.GetBoards.GetBoards

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, cmd} <- ResumeBoardV1.new(%{repo: Wire.arg(payload, :repo), by: by}),
           {:ok, _version, _events} <- MaybeResumeBoard.dispatch(cmd),
           :ok <- GetBoards.await_deferred(cmd.board_id, 0),
           do: {:ok, %{board: %{board_id: cmd.board_id, repo: cmd.repo, deferred: 0}}}

    {:reply, Wire.reply(reply), state}
  end
end
