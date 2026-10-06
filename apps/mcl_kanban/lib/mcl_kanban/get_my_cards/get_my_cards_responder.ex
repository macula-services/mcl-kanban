defmodule MclKanban.GetMyCards.GetMyCardsResponder do
  # mcl-kanban/get_my_cards: no arguments. The cards the caller holds now. Enlisted agents only.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias MclKanban.Wire
  alias QueryBoards.GetCardsByHolder.GetCardsByHolder

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply = with {:ok, by} <- Actor.of_caller(payload), do: read(by, payload)
    {:reply, Wire.reply(reply), state}
  end

  defp read(by, _payload) do
    cards = GetCardsByHolder.get_cards_by_holder(by.node_id)
    {:ok, %{cards: Enum.map(cards, &Wire.card/1)}}
  end
end
