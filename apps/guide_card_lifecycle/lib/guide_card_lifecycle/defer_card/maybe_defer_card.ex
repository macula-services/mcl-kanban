defmodule GuideCardLifecycle.DeferCard.MaybeDeferCard do
  # Handler: the home crew's prioritiser or operator, or the owner (#29),
  # defers a queued card (#17). A deferred card is not a contender, so
  # deferring clears its rank and its pin: resumed, it comes back unranked and
  # is ranked afresh if wanted. A held card is not deferred; its holder
  # releases it first.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CardStatus, CrewName}
  alias GuideCardLifecycle.DeferCard.{CardDeferredV1, DeferCardV1}

  @who [:prioritiser, :owner]

  def handle_payload(state, payload), do: handle(state, struct(DeferCardV1, payload))

  def handle(%CardState{status: status} = card, %DeferCardV1{} = cmd) do
    cond do
      refusal = Actor.refused(cmd.by, @who, CrewName.home_crew_in(card)) ->
        {:error, refusal}

      CardStatus.has?(status, CardStatus.claimed()) ->
        {:error, :already_claimed}

      CardStatus.has?(status, CardStatus.deferred()) ->
        {:error, :already_deferred}

      true ->
        {:ok, [CardDeferredV1.new(cmd, deferred(status), %{reason: cmd.reason, rank: nil})]}
    end
  end

  defp deferred(status),
    do:
      status
      |> :evoq_bit_flags.unset(CardStatus.pinned())
      |> :evoq_bit_flags.set(CardStatus.deferred())

  def dispatch(%DeferCardV1{} = cmd),
    do: CardAggregate.dispatch(:defer_card, cmd.card_id, DeferCardV1.to_map(cmd))
end
