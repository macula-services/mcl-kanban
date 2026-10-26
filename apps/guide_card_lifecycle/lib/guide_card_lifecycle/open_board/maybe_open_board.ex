defmodule GuideCardLifecycle.OpenBoard.MaybeOpenBoard do
  # Handler: the supervisor, the operator or the owner opens a repo's board,
  # once, for the crew it names (#29): the owner for any crew, the others for
  # their own only.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.BoardAggregate
  alias GuideCardLifecycle.BoardState
  alias GuideCardLifecycle.OpenBoard.{BoardOpenedV1, OpenBoardV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(OpenBoardV1, payload))

  def handle(%BoardState{} = board, %OpenBoardV1{} = cmd) do
    cond do
      refusal = Actor.refused(cmd.by, @who, cmd.crew) -> {:error, refusal}
      BoardState.open?(board) -> {:error, :already_open}
      true -> {:ok, [BoardOpenedV1.from_command(cmd)]}
    end
  end

  def dispatch(%OpenBoardV1{} = cmd) do
    :evoq_command.new(:open_board, BoardAggregate, cmd.board_id, OpenBoardV1.to_map(cmd))
    |> :evoq_router.dispatch()
  end
end
