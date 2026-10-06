defmodule GuideCardLifecycle.CardEvent do
  # What every card event carries besides its own fields: the card, the
  # status after the event, who acted (owner or agent, by name and node id)
  # and when.
  @moduledoc false

  alias GuideCardLifecycle.Actor

  @spec new(String.t(), String.t(), Actor.t(), non_neg_integer(), map()) :: map()
  def new(event_type, card_id, %Actor{} = by, status, fields) do
    by
    |> Actor.record()
    |> Map.merge(%{
      event_type: event_type,
      card_id: card_id,
      status: status,
      at: System.system_time(:millisecond)
    })
    |> Map.merge(fields)
  end
end
