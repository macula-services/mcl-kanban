defmodule MclKanban.ClaimNextCard.ClaimNextCardResponder do
  # mcl-kanban/claim_next_card: no arguments. Claims the caller's next card:
  # its own lane first, then unreserved, by rank, then age. Another agent may
  # take a candidate between the read and the claim, so it claims down the
  # list; a card lost that way is skipped. Replies the card, or reason
  # board_empty.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.ClaimCard.{ClaimCardV1, MaybeClaimCard}
  alias MclKanban.Wire
  alias QueryBoards.GetNextCardForAgent.GetNextCardForAgent

  @candidates 25
  @lost [:already_claimed, :not_in_lane, :blocked, :finished, :withdrawn, :package_card]

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           do:
             by.node_id
             |> GetNextCardForAgent.get_next_card_for_agent(@candidates)
             |> claim_first(by)

    {:reply, Wire.reply(reply), state}
  end

  defp claim_first([], _by), do: {:error, :board_empty}

  defp claim_first([candidate | rest], by) do
    {:ok, cmd} = ClaimCardV1.new(%{card_id: candidate.card_id, by: by})

    case MaybeClaimCard.dispatch(cmd) do
      {:ok, version, _events} -> Wire.card_after(cmd.card_id, version)
      {:error, reason} when reason in @lost -> claim_first(rest, by)
      {:error, _} = error -> error
    end
  end
end
