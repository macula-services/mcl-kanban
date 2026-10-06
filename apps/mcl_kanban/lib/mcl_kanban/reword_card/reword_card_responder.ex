defmodule MclKanban.RewordCard.RewordCardResponder do
  # mcl-kanban/reword_card: card_id, title, optional story. Supervisor, holder. Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.RewordCard.{MaybeRewordCard, RewordCardV1}
  alias MclKanban.{CardProcedure, Wire}

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    args = %{
      card_id: Wire.arg(payload, :card_id),
      title: Wire.arg(payload, :title),
      story: Wire.story(payload)
    }

    {:reply, CardProcedure.call(payload, RewordCardV1, MaybeRewordCard, args), state}
  end
end
