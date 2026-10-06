defmodule GuideCardLifecycle.QueueCard.MaybeQueueCard do
  # Handler: any agent, the supervisor or the owner queues a card, unranked
  # (the bottom of the queue until the prioritiser ranks it). One card per
  # issue. The card's board must be open and not archived; that is checked
  # against the board's live aggregate before dispatch.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.BoardAggregate
  alias GuideCardLifecycle.BoardState
  alias GuideCardLifecycle.CardAggregate
  alias GuideCardLifecycle.CardState
  alias GuideCardLifecycle.CardStatus
  alias GuideCardLifecycle.QueueCard.{CardQueuedV1, QueueCardV1}

  @who [:agent, :owner]

  def handle_payload(state, payload), do: handle(state, struct(QueueCardV1, payload))

  def handle(%CardState{status: status}, %QueueCardV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      status != 0 -> {:error, :already_on_board}
      true -> {:ok, [queued(cmd)]}
    end
  end

  defp queued(cmd) do
    CardQueuedV1.new(cmd, CardStatus.queued(), %{
      issue_ref: cmd.issue_ref,
      repo: cmd.repo,
      board_id: cmd.board_id,
      title: cmd.title,
      story: cmd.story,
      kind: cmd.kind,
      tags: cmd.tags
    })
  end

  def dispatch(%QueueCardV1{} = cmd) do
    board = BoardAggregate.current(cmd.board_id)

    cond do
      not BoardState.open?(board) -> {:error, :unknown_board}
      BoardState.archived?(board) -> {:error, :board_archived}
      true -> CardAggregate.dispatch(:queue_card, cmd.card_id, QueueCardV1.to_map(cmd))
    end
  end
end
