defmodule GuideCardLifecycle.OpenBoard.MaybeOpenBoard do
  # Handler: the supervisor or the owner opens a repo's board, once.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.BoardAggregate
  alias GuideCardLifecycle.BoardState
  alias GuideCardLifecycle.OpenBoard.{BoardOpenedV1, OpenBoardV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(OpenBoardV1, payload))

  def handle(%BoardState{} = board, %OpenBoardV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      BoardState.open?(board) -> {:error, :already_open}
      true -> {:ok, [BoardOpenedV1.from_command(cmd)]}
    end
  end

  def dispatch(%OpenBoardV1{} = cmd) do
    :evoq_command.new(:open_board, BoardAggregate, cmd.board_id, OpenBoardV1.to_map(cmd))
    |> :evoq_router.dispatch()
  end
end
