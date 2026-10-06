defmodule GuideCardLifecycle.ArchiveBoard.MaybeArchiveBoard do
  # Handler: the supervisor or the owner archives an open board, once. An
  # archived board takes no new cards.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.ArchiveBoard.{ArchiveBoardV1, BoardArchivedV1}
  alias GuideCardLifecycle.BoardAggregate
  alias GuideCardLifecycle.BoardState

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(ArchiveBoardV1, payload))

  def handle(%BoardState{} = board, %ArchiveBoardV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      not BoardState.open?(board) -> {:error, :unknown_board}
      BoardState.archived?(board) -> {:error, :already_archived}
      true -> {:ok, [BoardArchivedV1.from_command(cmd)]}
    end
  end

  def dispatch(%ArchiveBoardV1{} = cmd) do
    :evoq_command.new(:archive_board, BoardAggregate, cmd.board_id, ArchiveBoardV1.to_map(cmd))
    |> :evoq_router.dispatch()
  end
end
