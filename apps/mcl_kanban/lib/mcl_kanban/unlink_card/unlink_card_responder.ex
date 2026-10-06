defmodule MclKanban.UnlinkCard.UnlinkCardResponder do
  # mcl-kanban/unlink_card: card_id, to_card_id, link. Any agent. Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.UnlinkCard.{MaybeUnlinkCard, UnlinkCardV1}
  alias MclKanban.{CardProcedure, Wire}

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    args = %{
      card_id: Wire.arg(payload, :card_id),
      to_card_id: Wire.arg(payload, :to_card_id),
      link: Wire.arg(payload, :link)
    }

    {:reply, CardProcedure.call(payload, UnlinkCardV1, MaybeUnlinkCard, args), state}
  end
end
