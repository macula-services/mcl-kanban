defmodule MclKanban.WithdrawCard.WithdrawCardResponder do
  # mcl-kanban/withdraw_card: card_id, optional reason. The supervisor. Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.WithdrawCard.{MaybeWithdrawCard, WithdrawCardV1}
  alias MclKanban.{CardProcedure, Wire}

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    args = %{card_id: Wire.arg(payload, :card_id), reason: Wire.arg(payload, :reason)}
    {:reply, CardProcedure.call(payload, WithdrawCardV1, MaybeWithdrawCard, args), state}
  end
end
