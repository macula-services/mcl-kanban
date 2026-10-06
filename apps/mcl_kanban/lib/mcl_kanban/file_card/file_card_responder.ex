defmodule MclKanban.FileCard.FileCardResponder do
  # mcl-kanban/file_card: card_id, package_ref (the package's issue, owner/repo#n). Supervisor. Files the card into an open work package. Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.FileCard.{FileCardV1, MaybeFileCard}
  alias MclKanban.{CardProcedure, Wire}

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    args = %{card_id: Wire.arg(payload, :card_id), package_ref: Wire.arg(payload, :package_ref)}
    {:reply, CardProcedure.call(payload, FileCardV1, MaybeFileCard, args), state}
  end
end
