defmodule MclKanban.FinishCard.FinishCardResponder do
  # mcl-kanban/finish_card: card_id, result. Holder only. Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.FinishCard.{MaybeFinishCard, FinishCardV1}
  alias MclKanban.{CardProcedure, Wire}

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    args = %{card_id: Wire.arg(payload, :card_id), result: Wire.arg(payload, :result)}
    {:reply, CardProcedure.call(payload, FinishCardV1, MaybeFinishCard, args), state}
  end
end
