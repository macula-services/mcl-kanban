defmodule MclKanban.BlockCard.BlockCardResponder do
  # mcl-kanban/block_card: card_id, reason. Holder, supervisor. Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.BlockCard.{MaybeBlockCard, BlockCardV1}
  alias MclKanban.{CardProcedure, Wire}

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    args = %{card_id: Wire.arg(payload, :card_id), reason: Wire.arg(payload, :reason)}
    {:reply, CardProcedure.call(payload, BlockCardV1, MaybeBlockCard, args), state}
  end
end
