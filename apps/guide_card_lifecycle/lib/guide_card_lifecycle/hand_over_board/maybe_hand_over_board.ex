defmodule GuideCardLifecycle.HandOverBoard.MaybeHandOverBoard do
  # Handler: the owner hands an opened board over to another crew (#29), so
  # the first crew to open a repo's board does not hold it forever. Its cards
  # and packages follow it: the board's home crew is read live on every card
  # and package command. Archived or not, the owner may hand it over.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.BoardAggregate
  alias GuideCardLifecycle.BoardState
  alias GuideCardLifecycle.HandOverBoard.{BoardHandedOverV1, HandOverBoardV1}

  @who [:owner]

  def handle_payload(state, payload), do: handle(state, struct(HandOverBoardV1, payload))

  def handle(%BoardState{} = board, %HandOverBoardV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      not BoardState.open?(board) -> {:error, :unknown_board}
      board.home_crew == cmd.crew -> {:error, :already_home_crew}
      true -> {:ok, [BoardHandedOverV1.from_command(cmd, board.home_crew)]}
    end
  end

  def dispatch(%HandOverBoardV1{} = cmd) do
    :evoq_command.new(:hand_over_board, BoardAggregate, cmd.board_id, HandOverBoardV1.to_map(cmd))
    |> :evoq_router.dispatch()
  end
end
