defmodule MclKanban.PrioritiseCard.PrioritiseCardResponder do
  # mcl-kanban/prioritise_card: card_id, rank, rationale. The prioritiser. Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.PrioritiseCard.{MaybePrioritiseCard, PrioritiseCardV1}
  alias MclKanban.{CardProcedure, Wire}

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    args = %{
      card_id: Wire.arg(payload, :card_id),
      rank: Wire.arg(payload, :rank),
      rationale: Wire.arg(payload, :rationale)
    }

    {:reply, CardProcedure.call(payload, PrioritiseCardV1, MaybePrioritiseCard, args), state}
  end
end
