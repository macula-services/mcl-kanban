defmodule GuideCardLifecycle.ReleaseCard.MaybeReleaseCard do
  # Handler: the holder, the home crew's supervisor or operator (#29), or the
  # owner puts a claimed card back in the queue, with a reason. A blocked card stays blocked.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CardStatus, CrewName}
  alias GuideCardLifecycle.ReleaseCard.{CardReleasedV1, ReleaseCardV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(ReleaseCardV1, payload))

  def handle(%CardState{status: status} = card, %ReleaseCardV1{by: by} = cmd) do
    cond do
      not CardStatus.has?(status, CardStatus.claimed()) ->
        {:error, :not_claimed}

      refusal = steer_refusal(by, card) ->
        {:error, refusal}

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

  def dispatch(%ReleaseCardV1{} = cmd),
    do: CardAggregate.dispatch(:release_card, cmd.card_id, ReleaseCardV1.to_map(cmd))
end
