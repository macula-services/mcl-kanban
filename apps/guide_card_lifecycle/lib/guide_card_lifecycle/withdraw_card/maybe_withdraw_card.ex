defmodule GuideCardLifecycle.WithdrawCard.MaybeWithdrawCard do
  # Handler: the supervisor or the owner takes a card off the board without
  # it being done.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CardStatus}
  alias GuideCardLifecycle.WithdrawCard.{CardWithdrawnV1, WithdrawCardV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(WithdrawCardV1, payload))

  def handle(%CardState{status: status}, %WithdrawCardV1{} = cmd) do
    case Actor.allowed?(cmd.by, @who) do
      true ->
        {:ok,
         [
           CardWithdrawnV1.new(cmd, CardStatus.to_closed(status, CardStatus.withdrawn()), %{
             reason: cmd.reason
           })
         ]}

      false ->
        {:error, :not_permitted}
    end
  end

  def dispatch(%WithdrawCardV1{} = cmd),
    do: CardAggregate.dispatch(:withdraw_card, cmd.card_id, WithdrawCardV1.to_map(cmd))
end
