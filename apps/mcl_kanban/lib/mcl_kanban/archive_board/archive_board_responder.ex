defmodule MclKanban.ArchiveBoard.ArchiveBoardResponder do
  # mcl-kanban/archive_board: repo. The supervisor archives a board; it takes no new cards. Replies the board.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.ArchiveBoard.{MaybeArchiveBoard, ArchiveBoardV1}
  alias MclKanban.Wire

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, cmd} <- ArchiveBoardV1.new(Map.put(%{repo: Wire.arg(payload, :repo)}, :by, by)),
           {:ok, _version, _events} <- MaybeArchiveBoard.dispatch(cmd),
           do: {:ok, %{board: %{board_id: cmd.board_id, repo: cmd.repo}}}

    {:reply, Wire.reply(reply), state}
  end
end
