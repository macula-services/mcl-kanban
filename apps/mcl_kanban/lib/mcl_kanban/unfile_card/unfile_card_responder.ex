defmodule MclKanban.UnfileCard.UnfileCardResponder do
  # mcl-kanban/unfile_card: card_id. Supervisor. Takes the card out of its work package. Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.UnfileCard.{MaybeUnfileCard, UnfileCardV1}
  alias MclKanban.{CardProcedure, Wire}

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    args = %{card_id: Wire.arg(payload, :card_id)}
    {:reply, CardProcedure.call(payload, UnfileCardV1, MaybeUnfileCard, args), state}
  end
end
