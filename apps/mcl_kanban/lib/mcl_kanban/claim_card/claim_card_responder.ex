defmodule MclKanban.ClaimCard.ClaimCardResponder do
  # mcl-kanban/claim_card: card_id. Claim the card; the caller becomes its
  # holder. Replies the card, with the crew's goal sentence (#18).
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.ClaimCard.{ClaimCardV1, MaybeClaimCard}
  alias MclKanban.Wire

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, cmd} <- ClaimCardV1.new(%{card_id: Wire.arg(payload, :card_id), by: by}),
           {:ok, version, _events} <- MaybeClaimCard.dispatch(cmd),
           do: Wire.card_after(cmd.card_id, version)

    {:reply, reply |> Wire.with_goal() |> Wire.reply(), state}
  end
end
