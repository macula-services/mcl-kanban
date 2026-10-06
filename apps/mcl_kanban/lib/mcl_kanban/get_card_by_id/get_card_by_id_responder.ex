defmodule MclKanban.GetCardById.GetCardByIdResponder do
  # mcl-kanban/get_card_by_id: card_id. The card with its links both ways and its comment thread. Enlisted agents only.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias MclKanban.Wire
  alias QueryBoards.GetCardById.GetCardById

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply = with {:ok, by} <- Actor.of_caller(payload), do: read(by, payload)
    {:reply, Wire.reply(reply), state}
  end

  defp read(_by, payload) do
    with {:ok, card} <- GetCardById.get_card_by_id(Wire.arg(payload, :card_id)),
         do: {:ok, %{card: Wire.card(card)}}
  end
end
