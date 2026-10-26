defmodule GuideCardLifecycle.BlockCard.MaybeBlockCard do
  # Handler: the holder, the home crew's supervisor or operator (#29), or the
  # owner blocks a card, with a reason. A blocked card cannot be claimed or finished.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CardStatus, CrewName}
  alias GuideCardLifecycle.BlockCard.{BlockCardV1, CardBlockedV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(BlockCardV1, payload))

  def handle(%CardState{status: status} = card, %BlockCardV1{by: by} = cmd) do
    cond do
      refusal = steer_refusal(by, card) ->
        {:error, refusal}

      CardStatus.has?(status, CardStatus.blocked()) ->
        {:error, :already_blocked}

      true ->
        {:ok,
         [
           CardBlockedV1.new(cmd, :evoq_bit_flags.set(status, CardStatus.blocked()), %{
             reason: cmd.reason
           })
         ]}
    end
  end

  # The holder may, whatever its crew; otherwise the home crew's supervisor
  # or operator, or the owner (#29). Another crew's supervisor is told why;
  # anyone else is simply not the holder.
  defp steer_refusal(by, card) do
    holder_refusal(
      Actor.holds?(by, card.holder_node_id),
      Actor.refused(by, @who, CrewName.home_crew_in(card))
    )
  end

  defp holder_refusal(true, _refusal), do: nil
  defp holder_refusal(false, :not_permitted), do: :not_holder
  defp holder_refusal(false, refusal), do: refusal

  def dispatch(%BlockCardV1{} = cmd),
    do: CardAggregate.dispatch(:block_card, cmd.card_id, BlockCardV1.to_map(cmd))
end
