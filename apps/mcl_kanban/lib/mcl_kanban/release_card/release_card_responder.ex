defmodule MclKanban.ReleaseCard.ReleaseCardResponder do
  # mcl-kanban/release_card: card_id, reason. Back in the queue (holder, supervisor). Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.ReleaseCard.{MaybeReleaseCard, ReleaseCardV1}
  alias MclKanban.{CardProcedure, Wire}

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    args = %{card_id: Wire.arg(payload, :card_id), reason: Wire.arg(payload, :reason)}
    {:reply, CardProcedure.call(payload, ReleaseCardV1, MaybeReleaseCard, args), state}
  end
end
