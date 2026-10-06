defmodule GuideCardLifecycle.ClaimCard.MaybeClaimCard do
  # Handler: an enlisted agent claims a queued card that is in its lane, or
  # in no lane. A holder is always an agent, so the owner never claims. The
  # card's own stream serialises claims: the second gets already_claimed.
  @moduledoc false

  alias GuideCardLifecycle.{CardAggregate, CardState, CardStatus}
  alias GuideCardLifecycle.ClaimCard.{CardClaimedV1, ClaimCardV1}

  def handle_payload(state, payload), do: handle(state, struct(ClaimCardV1, payload))

  def handle(%CardState{status: status} = card, %ClaimCardV1{by: by} = cmd) do
    cond do
      by.kind != :agent -> {:error, :not_permitted}
      CardStatus.has?(status, CardStatus.claimed()) -> {:error, :already_claimed}
      CardStatus.has?(status, CardStatus.blocked()) -> {:error, :blocked}
      card.lane_node_id not in [nil, by.node_id] -> {:error, :not_in_lane}
      true -> {:ok, [claimed(cmd, status)]}
    end
  end

  defp claimed(cmd, status),
    do:
      CardClaimedV1.new(cmd, CardStatus.to_claimed(status), %{
        holder: cmd.by.name,
        holder_node_id: cmd.by.node_id
      })

  def dispatch(%ClaimCardV1{} = cmd),
    do: CardAggregate.dispatch(:claim_card, cmd.card_id, ClaimCardV1.to_map(cmd))
end
