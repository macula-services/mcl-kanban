defmodule MclKanban.GetApprovals.GetApprovalsResponder do
  # mcl-kanban/get_approvals: card_id. The signed approvals on the card,
  # oldest first, each with its encoded object (base64 text) to re-verify
  # (#30). Enlisted agents of any crew.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias MclKanban.Wire
  alias QueryBoards.GetApprovals.GetApprovals

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, _by} <- Actor.of_caller(payload),
           {:ok, approvals} <- GetApprovals.get_approvals(Wire.arg(payload, :card_id)),
           do: {:ok, %{approvals: approvals}}

    {:reply, Wire.reply(reply), state}
  end
end
