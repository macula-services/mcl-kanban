defmodule MclKanban.TagCard.TagCardResponder do
  # mcl-kanban/tag_card: card_id, tag. Any agent. Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.TagCard.{MaybeTagCard, TagCardV1}
  alias MclKanban.{CardProcedure, Wire}

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    args = %{card_id: Wire.arg(payload, :card_id), tag: Wire.arg(payload, :tag)}
    {:reply, CardProcedure.call(payload, TagCardV1, MaybeTagCard, args), state}
  end
end
