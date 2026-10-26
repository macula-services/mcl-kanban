defmodule GuideCardLifecycle.DeferBoard.MaybeDeferBoard do
  # Handler: the home crew's prioritiser or operator, or the owner (#29),
  # pauses a repo (#17): its cards stay queued and are not handed out until
  # the board is resumed. No card is marked blocked.
  @moduledoc false

  alias GuideCardLifecycle.CrewName
  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.BoardState
  alias GuideCardLifecycle.DeferBoard.{BoardDeferredV1, DeferBoardV1}

  @who [:prioritiser, :owner]

  def handle_payload(state, payload), do: handle(state, struct(DeferBoardV1, payload))

  def handle(%BoardState{} = board, %DeferBoardV1{} = cmd) do
    cond do
      refusal = Actor.refused(cmd.by, @who, CrewName.home_crew_in(board)) ->
        {:error, refusal}

      not BoardState.open?(board) ->
        {:error, :unknown_board}

      BoardState.deferred?(board) ->
        {:error, :already_deferred}

      true ->
        {:ok, [BoardDeferredV1.from_command(cmd, %{reason: cmd.reason})]}
    end
  end

  def dispatch(%DeferBoardV1{} = cmd) do
    :evoq_command.new(
      :defer_board,
      GuideCardLifecycle.BoardAggregate,
      cmd.board_id,
      DeferBoardV1.to_map(cmd)
    )
    |> :evoq_router.dispatch()
  end
end
