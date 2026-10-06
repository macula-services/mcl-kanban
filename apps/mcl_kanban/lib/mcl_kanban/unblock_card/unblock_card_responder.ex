defmodule MclKanban.UnblockCard.UnblockCardResponder do
  # mcl-kanban/unblock_card: card_id. Holder, supervisor. Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.UnblockCard.{MaybeUnblockCard, UnblockCardV1}
  alias MclKanban.{CardProcedure, Wire}

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    args = %{card_id: Wire.arg(payload, :card_id)}
    {:reply, CardProcedure.call(payload, UnblockCardV1, MaybeUnblockCard, args), state}
  end
end
