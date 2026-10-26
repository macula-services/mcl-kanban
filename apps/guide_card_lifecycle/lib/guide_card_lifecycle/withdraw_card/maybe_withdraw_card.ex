defmodule GuideCardLifecycle.WithdrawCard.MaybeWithdrawCard do
  # Handler: the home crew's supervisor or operator, or the owner, takes a
  # card off the board without it being done (#29).
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CardStatus, CrewName}
  alias GuideCardLifecycle.WithdrawCard.{CardWithdrawnV1, WithdrawCardV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(WithdrawCardV1, payload))

  def handle(%CardState{status: status} = card, %WithdrawCardV1{} = cmd) do
    case Actor.refused(cmd.by, @who, CrewName.home_crew_in(card)) do
      nil ->
        {:ok,
         [
           CardWithdrawnV1.new(cmd, CardStatus.to_closed(status, CardStatus.withdrawn()), %{
             reason: cmd.reason
           })
         ]}

      refusal ->
        {:error, refusal}
    end
  end

  def dispatch(%WithdrawCardV1{} = cmd),
    do: CardAggregate.dispatch(:withdraw_card, cmd.card_id, WithdrawCardV1.to_map(cmd))
end
