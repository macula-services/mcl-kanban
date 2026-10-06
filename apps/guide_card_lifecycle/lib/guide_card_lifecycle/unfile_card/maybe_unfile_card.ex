defmodule GuideCardLifecycle.UnfileCard.MaybeUnfileCard do
  # Handler: the supervisor or the owner takes a card out of its package.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState}
  alias GuideCardLifecycle.UnfileCard.{CardUnfiledV1, UnfileCardV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(UnfileCardV1, payload))

  def handle(%CardState{status: status} = card, %UnfileCardV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      card.work_package == nil -> {:error, :not_filed}
      true -> {:ok, [CardUnfiledV1.new(cmd, status, %{work_package: card.work_package})]}
    end
  end

  def dispatch(%UnfileCardV1{} = cmd),
    do: CardAggregate.dispatch(:unfile_card, cmd.card_id, UnfileCardV1.to_map(cmd))
end
