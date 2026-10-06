defmodule MclKanban.ReserveCard.ReserveCardResponder do
  # mcl-kanban/reserve_card: card_id, lane (an agent name). Supervisor, prioritiser. Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.ReserveCard.{MaybeReserveCard, ReserveCardV1}
  alias MclKanban.{CardProcedure, Wire}

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    args = %{card_id: Wire.arg(payload, :card_id), lane: Wire.arg(payload, :lane)}
    {:reply, CardProcedure.call(payload, ReserveCardV1, MaybeReserveCard, args), state}
  end
end
