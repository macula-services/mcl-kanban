defmodule GuideCardLifecycle.FinishCard.MaybeFinishCard do
  # Handler: ONLY the holder finishes, with a one-line result. Not the
  # supervisor and not the owner: finishing says "I did this work". The agent
  # still closes the GitHub issue with its result; the board never calls
  # GitHub.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CardStatus}
  alias GuideCardLifecycle.FinishCard.{CardFinishedV1, FinishCardV1}

  def handle_payload(state, payload), do: handle(state, struct(FinishCardV1, payload))

  def handle(%CardState{status: status} = card, %FinishCardV1{by: by} = cmd) do
    cond do
      not Actor.holds?(by, card.holder_node_id) ->
        {:error, :not_holder}

      CardStatus.has?(status, CardStatus.blocked()) ->
        {:error, :blocked}

      true ->
        {:ok,
         [
           CardFinishedV1.new(cmd, CardStatus.to_closed(status, CardStatus.finished()), %{
             result: cmd.result
           })
         ]}
    end
  end

  def dispatch(%FinishCardV1{} = cmd),
    do: CardAggregate.dispatch(:finish_card, cmd.card_id, FinishCardV1.to_map(cmd))
end
