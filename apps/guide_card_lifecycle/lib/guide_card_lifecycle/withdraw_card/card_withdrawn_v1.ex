defmodule GuideCardLifecycle.WithdrawCard.CardWithdrawnV1 do
  # Event: card_withdrawn_v1.
  @moduledoc false

  alias GuideCardLifecycle.CardEvent

  def event_type, do: "card_withdrawn_v1"

  def new(cmd, status, fields \\ %{}),
    do: CardEvent.new(event_type(), cmd.card_id, cmd.by, status, fields)
end
