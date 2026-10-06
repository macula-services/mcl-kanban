defmodule GuideCardLifecycle.BoardAggregate do
  # The board of one repo: opened and archived by the supervisor or the owner.
  @moduledoc false

  @behaviour :evoq_aggregate

  alias GuideCardLifecycle.ArchiveBoard.MaybeArchiveBoard
  alias GuideCardLifecycle.BoardState
  alias GuideCardLifecycle.DeferBoard.MaybeDeferBoard
  alias GuideCardLifecycle.LiveState
  alias GuideCardLifecycle.OpenBoard.MaybeOpenBoard
  alias GuideCardLifecycle.ResumeBoard.MaybeResumeBoard

  @doc "The board as the live aggregate holds it now."
  @spec current(String.t()) :: BoardState.t()
  def current(board_id), do: LiveState.of(__MODULE__, board_id)

  @impl true
  def state_module, do: BoardState

  @impl true
  def init(board_id), do: {:ok, BoardState.new(board_id)}

  @impl true
  def apply(state, event), do: BoardState.apply_event(state, event)

  @impl true
  def execute(state, %{command_type: :open_board} = p),
    do: MaybeOpenBoard.handle_payload(state, p)

  def execute(state, %{command_type: :archive_board} = p),
    do: MaybeArchiveBoard.handle_payload(state, p)

  def execute(state, %{command_type: :defer_board} = p),
    do: MaybeDeferBoard.handle_payload(state, p)

  def execute(state, %{command_type: :resume_board} = p),
    do: MaybeResumeBoard.handle_payload(state, p)

  def execute(_state, _payload), do: {:error, :unknown_command}
end
