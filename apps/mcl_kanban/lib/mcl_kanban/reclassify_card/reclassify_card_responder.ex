defmodule MclKanban.ReclassifyCard.ReclassifyCardResponder do
  # mcl-kanban/reclassify_card: card_id, kind. The supervisor. Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.ReclassifyCard.{MaybeReclassifyCard, ReclassifyCardV1}
  alias MclKanban.{CardProcedure, Wire}

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    args = %{card_id: Wire.arg(payload, :card_id), kind: Wire.arg(payload, :kind)}
    {:reply, CardProcedure.call(payload, ReclassifyCardV1, MaybeReclassifyCard, args), state}
  end
end
