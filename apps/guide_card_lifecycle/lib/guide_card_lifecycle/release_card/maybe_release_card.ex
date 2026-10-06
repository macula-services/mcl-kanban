defmodule GuideCardLifecycle.ReleaseCard.MaybeReleaseCard do
  # Handler: the holder, the supervisor or the owner puts a claimed card back
  # in the queue, with a reason. A blocked card stays blocked.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CardStatus}
  alias GuideCardLifecycle.ReleaseCard.{CardReleasedV1, ReleaseCardV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(ReleaseCardV1, payload))

  def handle(%CardState{status: status} = card, %ReleaseCardV1{by: by} = cmd) do
    cond do
      not CardStatus.has?(status, CardStatus.claimed()) ->
        {:error, :not_claimed}

      not (Actor.allowed?(by, @who) or Actor.holds?(by, card.holder_node_id)) ->
        {:error, :not_holder}

      true ->
        {:ok,
         [
           CardReleasedV1.new(cmd, CardStatus.to_queue(status), %{
             reason: cmd.reason,
             holder: card.holder
           })
         ]}
    end
  end

  def dispatch(%ReleaseCardV1{} = cmd),
    do: CardAggregate.dispatch(:release_card, cmd.card_id, ReleaseCardV1.to_map(cmd))
end
