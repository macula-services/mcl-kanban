defmodule GuideCardLifecycle.CardAggregate do
  # One card per stream, so two agents claiming the same card at once are
  # serialised here: one gets it, the other gets already_claimed.
  #
  # Blanket rules before any desk: a card that was never queued is
  # unknown_card; a finished or withdrawn card refuses everything except
  # tags, links, comments and approvals.
  #
  # A card follows its board's home crew (#29), and the owner may hand a
  # board over, so dispatch/3 reads the board's crew live and puts it on the
  # command; execute/2 decides with it in place of the crew the card was
  # queued under. Nothing a caller sends reaches that key: commands are built
  # from named arguments, and dispatch/3 writes it.
  @moduledoc false

  @behaviour :evoq_aggregate

  alias GuideCardLifecycle.DeferCard.MaybeDeferCard
  alias GuideCardLifecycle.ResumeCard.MaybeResumeCard
  alias GuideCardLifecycle.CardState
  alias GuideCardLifecycle.BoardAggregate
  alias GuideCardLifecycle.CardStatus
  alias GuideCardLifecycle.LiveState

  alias GuideCardLifecycle.BlockCard.MaybeBlockCard
  alias GuideCardLifecycle.ClaimCard.MaybeClaimCard
  alias GuideCardLifecycle.CommentOnCard.MaybeCommentOnCard
  alias GuideCardLifecycle.FileCard.MaybeFileCard
  alias GuideCardLifecycle.FinishCard.MaybeFinishCard
  alias GuideCardLifecycle.LiftCardReservation.MaybeLiftCardReservation
  alias GuideCardLifecycle.LinkCard.MaybeLinkCard
  alias GuideCardLifecycle.PrioritiseCard.MaybePrioritiseCard
  alias GuideCardLifecycle.QueueCard.MaybeQueueCard
  alias GuideCardLifecycle.RecordApproval.MaybeRecordApproval
  alias GuideCardLifecycle.ReclassifyCard.MaybeReclassifyCard
  alias GuideCardLifecycle.ReleaseCard.MaybeReleaseCard
  alias GuideCardLifecycle.ReserveCard.MaybeReserveCard
  alias GuideCardLifecycle.RewordCard.MaybeRewordCard
  alias GuideCardLifecycle.TagCard.MaybeTagCard
  alias GuideCardLifecycle.UnblockCard.MaybeUnblockCard
  alias GuideCardLifecycle.UnfileCard.MaybeUnfileCard
  alias GuideCardLifecycle.UnlinkCard.MaybeUnlinkCard
  alias GuideCardLifecycle.UnpinCard.MaybeUnpinCard
  alias GuideCardLifecycle.UntagCard.MaybeUntagCard
  alias GuideCardLifecycle.WithdrawCard.MaybeWithdrawCard

  @desks %{
    reword_card: MaybeRewordCard,
    reclassify_card: MaybeReclassifyCard,
    tag_card: MaybeTagCard,
    untag_card: MaybeUntagCard,
    prioritise_card: MaybePrioritiseCard,
    unpin_card: MaybeUnpinCard,
    reserve_card: MaybeReserveCard,
    lift_card_reservation: MaybeLiftCardReservation,
    claim_card: MaybeClaimCard,
    release_card: MaybeReleaseCard,
    block_card: MaybeBlockCard,
    unblock_card: MaybeUnblockCard,
    finish_card: MaybeFinishCard,
    withdraw_card: MaybeWithdrawCard,
    link_card: MaybeLinkCard,
    unlink_card: MaybeUnlinkCard,
    comment_on_card: MaybeCommentOnCard,
    file_card: MaybeFileCard,
    unfile_card: MaybeUnfileCard,
    defer_card: MaybeDeferCard,
    resume_card: MaybeResumeCard,
    record_approval: MaybeRecordApproval
  }

  @after_close [
    :tag_card,
    :untag_card,
    :link_card,
    :unlink_card,
    :comment_on_card,
    :record_approval
  ]

  @doc "The card as the live aggregate holds it now."
  @spec current(String.t()) :: CardState.t()
  def current(card_id), do: LiveState.of(__MODULE__, card_id)

  @impl true
  def state_module, do: CardState

  @impl true
  def init(card_id), do: {:ok, CardState.new(card_id)}

  @impl true
  def apply(state, event), do: CardState.apply_event(state, event)

  @impl true
  def execute(state, %{command_type: :queue_card} = p),
    do: MaybeQueueCard.handle_payload(state, p)

  def execute(%CardState{status: 0}, _payload), do: {:error, :unknown_card}

  def execute(%CardState{status: status} = card, %{command_type: type} = p) do
    state = on_board(card, p)

    cond do
      type in @after_close -> route(state, type, p)
      CardStatus.has?(status, CardStatus.finished()) -> {:error, :finished}
      CardStatus.has?(status, CardStatus.withdrawn()) -> {:error, :withdrawn}
      true -> route(state, type, p)
    end
  end

  def execute(_state, _payload), do: {:error, :unknown_command}

  defp on_board(card, %{home_crew: crew}) when is_binary(crew), do: %{card | home_crew: crew}
  defp on_board(card, _payload), do: card

  defp route(state, type, payload), do: routed(Map.get(@desks, type), state, payload)

  defp routed(nil, _state, _payload), do: {:error, :unknown_command}
  defp routed(desk, state, payload), do: desk.handle_payload(state, payload)

  @doc "Dispatches a card command to its card's stream."
  @spec dispatch(atom(), String.t(), map()) ::
          {:ok, non_neg_integer(), [map()]} | {:error, term()}
  def dispatch(command_type, card_id, payload) do
    # queue_card brings the crew of the board it opens the card on.
    payload = Map.put_new_lazy(payload, :home_crew, fn -> board_crew(current(card_id)) end)

    :evoq_command.new(command_type, __MODULE__, card_id, payload)
    |> :evoq_router.dispatch()
  end

  defp board_crew(%CardState{board_id: nil}), do: nil
  defp board_crew(%CardState{board_id: board_id}), do: BoardAggregate.current(board_id).home_crew
end
