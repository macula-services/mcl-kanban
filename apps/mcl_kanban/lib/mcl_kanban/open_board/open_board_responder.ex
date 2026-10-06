defmodule MclKanban.OpenBoard.OpenBoardResponder do
  # mcl-kanban/open_board: repo (owner/repo). The supervisor opens a repo's board. Replies the board.
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
           {:ok, cmd} <- OpenBoardV1.new(Map.put(%{repo: Wire.arg(payload, :repo)}, :by, by)),
           {:ok, _version, _events} <- MaybeOpenBoard.dispatch(cmd),
           do: {:ok, %{board: %{board_id: cmd.board_id, repo: cmd.repo}}}

    {:reply, Wire.reply(reply), state}
  end
end
