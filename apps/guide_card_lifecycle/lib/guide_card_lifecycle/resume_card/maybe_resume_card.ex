defmodule GuideCardLifecycle.ResumeCard.MaybeResumeCard do
  # Handler: the prioritiser or the owner resumes a deferred card (#17). It
  # is queued again, unranked.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CardStatus}
  alias GuideCardLifecycle.ResumeCard.{CardResumedV1, ResumeCardV1}

  @who [:prioritiser, :owner]

  def handle_payload(state, payload), do: handle(state, struct(ResumeCardV1, payload))

  def handle(%CardState{status: status}, %ResumeCardV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) ->
        {:error, :not_permitted}

      not CardStatus.has?(status, CardStatus.deferred()) ->
        {:error, :not_deferred}

      true ->
        {:ok, [CardResumedV1.new(cmd, :evoq_bit_flags.unset(status, CardStatus.deferred()))]}
    end
  end

  def dispatch(%ResumeCardV1{} = cmd),
    do: CardAggregate.dispatch(:resume_card, cmd.card_id, ResumeCardV1.to_map(cmd))
end
