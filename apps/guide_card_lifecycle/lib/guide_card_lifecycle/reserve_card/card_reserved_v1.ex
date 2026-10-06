defmodule GuideCardLifecycle.ReserveCard.CardReservedV1 do
  # Event: card_reserved_v1.
  @moduledoc false

  alias GuideCardLifecycle.CardEvent

  def event_type, do: "card_reserved_v1"

  def new(cmd, status, fields \\ %{}),
    do: CardEvent.new(event_type(), cmd.card_id, cmd.by, status, fields)
end
