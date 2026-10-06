defmodule GuideCardLifecycle.ClaimCard.MaybeClaimCard do
  # Handler: an enlisted agent claims a queued card that is in its lane, or
  # in no lane. A holder is always an agent, so the owner never claims. The
  # card's own stream serialises claims: the second gets already_claimed.
  #
  # A package's own card (filed into itself) is never claimed (#15): packages
  # only group and order cards, so a member holds ordinary cards and nothing
  # more. Holding a package card read as owning the package, and two members
  # worked the same issue three times on the first day.
  @moduledoc false

  alias GuideCardLifecycle.{CardAggregate, CardState, CardStatus}
  alias GuideCardLifecycle.ClaimCard.{CardClaimedV1, ClaimCardV1}

  def handle_payload(state, payload), do: handle(state, struct(ClaimCardV1, payload))

  def handle(%CardState{status: status} = card, %ClaimCardV1{by: by} = cmd) do
    cond do
      by.kind != :agent -> {:error, :not_permitted}
      card.work_package != nil and card.work_package == card.issue_ref -> {:error, :package_card}
      CardStatus.has?(status, CardStatus.claimed()) -> {:error, :already_claimed}
      CardStatus.has?(status, CardStatus.blocked()) -> {:error, :blocked}
      CardStatus.has?(status, CardStatus.deferred()) -> {:error, :deferred}
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
