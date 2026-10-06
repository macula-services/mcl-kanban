defmodule MclKanban.LinkCard.LinkCardResponder do
  # mcl-kanban/link_card: card_id, to_card_id, link (blocks, relates_to, follows_up). Any agent. Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.LinkCard.{MaybeLinkCard, LinkCardV1}
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

    {:reply, CardProcedure.call(payload, LinkCardV1, MaybeLinkCard, args), state}
  end
end
