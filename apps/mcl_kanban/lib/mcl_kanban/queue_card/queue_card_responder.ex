defmodule MclKanban.QueueCard.QueueCardResponder do
  # mcl-kanban/queue_card: issue_ref (owner/repo#n), title, kind (bug, slice,
  # ui), optional story {role, ask, value} and tags. Any enlisted agent. The
  # card lands on its repo's board, unranked. Replies card_id.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.QueueCard.{MaybeQueueCard, QueueCardV1}
  alias MclKanban.Wire

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, cmd} <-
             QueueCardV1.new(%{
               issue_ref: Wire.arg(payload, :issue_ref),
               title: Wire.arg(payload, :title),
               kind: Wire.arg(payload, :kind),
               story: Wire.story(payload),
               tags: Wire.arg(payload, :tags),
               by: by
             }),
           {:ok, version, _events} <- MaybeQueueCard.dispatch(cmd),
           do: Wire.once_read(cmd.card_id, version, %{card_id: cmd.card_id})

    {:reply, Wire.reply(reply), state}
  end
end
