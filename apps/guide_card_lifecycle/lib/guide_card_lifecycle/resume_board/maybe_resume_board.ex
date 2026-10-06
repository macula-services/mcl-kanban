defmodule GuideCardLifecycle.ResumeBoard.MaybeResumeBoard do
  # Handler: the prioritiser or the owner resumes a paused repo (#17).
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.BoardState
  alias GuideCardLifecycle.ResumeBoard.{BoardResumedV1, ResumeBoardV1}

  @who [:prioritiser, :owner]

  def handle_payload(state, payload), do: handle(state, struct(ResumeBoardV1, payload))

  def handle(%BoardState{} = board, %ResumeBoardV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      not BoardState.open?(board) -> {:error, :unknown_board}
      not BoardState.deferred?(board) -> {:error, :not_deferred}
      true -> {:ok, [BoardResumedV1.from_command(cmd)]}
    end
  end

  def dispatch(%ResumeBoardV1{} = cmd) do
    :evoq_command.new(
      :resume_board,
      GuideCardLifecycle.BoardAggregate,
      cmd.board_id,
      ResumeBoardV1.to_map(cmd)
    )
    |> :evoq_router.dispatch()
  end
end
