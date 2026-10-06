defmodule MclKanban.DeferCard.DeferCardResponder do
  # mcl-kanban/defer_card: card_id, reason. The prioritiser or the owner defers a queued card: not
  # handed out, unranked, until resumed (#17). Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.DeferCard.{MaybeDeferCard, DeferCardV1}
  alias MclKanban.{CardProcedure, Wire}

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    args = %{card_id: Wire.arg(payload, :card_id), reason: Wire.arg(payload, :reason)}
    {:reply, CardProcedure.call(payload, DeferCardV1, MaybeDeferCard, args), state}
  end
end
