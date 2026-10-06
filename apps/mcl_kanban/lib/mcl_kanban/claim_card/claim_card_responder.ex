defmodule MclKanban.ClaimCard.ClaimCardResponder do
  # mcl-kanban/claim_card: card_id. Claim the card; the caller becomes its holder. Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.ClaimCard.{MaybeClaimCard, ClaimCardV1}
  alias MclKanban.{CardProcedure, Wire}

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    args = %{card_id: Wire.arg(payload, :card_id)}
    {:reply, CardProcedure.call(payload, ClaimCardV1, MaybeClaimCard, args), state}
  end
end
