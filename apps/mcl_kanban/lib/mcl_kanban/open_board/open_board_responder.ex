defmodule MclKanban.OpenBoard.OpenBoardResponder do
  # mcl-kanban/open_board: repo (owner/repo), optional crew (#29): the board's
  # home crew, by default the caller's. The supervisor or an operator opens a
  # board for its own crew. Replies the board with its home crew.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.OpenBoard.{MaybeOpenBoard, OpenBoardV1}
  alias MclKanban.Wire

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, cmd} <-
             OpenBoardV1.new(%{
               repo: Wire.arg(payload, :repo),
               crew: Wire.arg(payload, :crew),
               by: by
             }),
           {:ok, _version, _events} <- MaybeOpenBoard.dispatch(cmd),
           do: {:ok, %{board: %{board_id: cmd.board_id, repo: cmd.repo, home_crew: cmd.crew}}}

    {:reply, Wire.reply(reply), state}
  end
end
