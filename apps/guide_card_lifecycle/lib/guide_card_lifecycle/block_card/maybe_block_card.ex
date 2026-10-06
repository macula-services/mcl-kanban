defmodule GuideCardLifecycle.BlockCard.MaybeBlockCard do
  # Handler: the holder, the supervisor or the owner blocks a card, with a
  # reason. A blocked card cannot be claimed or finished.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CardStatus}
  alias GuideCardLifecycle.BlockCard.{BlockCardV1, CardBlockedV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(BlockCardV1, payload))

  def handle(%CardState{status: status} = card, %BlockCardV1{by: by} = cmd) do
    cond do
      not (Actor.allowed?(by, @who) or Actor.holds?(by, card.holder_node_id)) ->
        {:error, :not_holder}

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

  def dispatch(%BlockCardV1{} = cmd),
    do: CardAggregate.dispatch(:block_card, cmd.card_id, BlockCardV1.to_map(cmd))
end
