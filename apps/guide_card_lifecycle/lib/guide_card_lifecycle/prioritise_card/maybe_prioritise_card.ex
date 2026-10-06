defmodule GuideCardLifecycle.PrioritiseCard.MaybePrioritiseCard do
  # Handler: the prioritiser or the owner ranks. An owner rank PINS the card:
  # the prioritiser cannot change it until the owner unpins.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CardStatus}
  alias GuideCardLifecycle.PrioritiseCard.{CardPrioritisedV1, PrioritiseCardV1}

  @who [:prioritiser, :owner]

  def handle_payload(state, payload), do: handle(state, struct(PrioritiseCardV1, payload))

  def handle(%CardState{status: status}, %PrioritiseCardV1{by: by} = cmd) do
    cond do
      not Actor.allowed?(by, @who) ->
        {:error, :not_permitted}

      CardStatus.has?(status, CardStatus.deferred()) ->
        {:error, :deferred}

      CardStatus.pinned?(status) and by.kind != :owner ->
        {:error, :pinned_by_owner}

      true ->
        {:ok,
         [
           CardPrioritisedV1.new(cmd, pinned(status, by), %{
             rank: cmd.rank,
             rationale: cmd.rationale
           })
         ]}
    end
  end

  defp pinned(status, %Actor{kind: :owner}), do: :evoq_bit_flags.set(status, CardStatus.pinned())
  defp pinned(status, %Actor{}), do: status

  def dispatch(%PrioritiseCardV1{} = cmd),
    do: CardAggregate.dispatch(:prioritise_card, cmd.card_id, PrioritiseCardV1.to_map(cmd))
end
