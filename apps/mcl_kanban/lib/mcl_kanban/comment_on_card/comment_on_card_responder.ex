defmodule MclKanban.CommentOnCard.CommentOnCardResponder do
  # mcl-kanban/comment_on_card: card_id, text. Any enlisted agent. Replies
  # comment_id.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CommentOnCard.{CommentOnCardV1, MaybeCommentOnCard}
  alias MclKanban.Wire

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, cmd} <-
             CommentOnCardV1.new(%{
               card_id: Wire.arg(payload, :card_id),
               text: Wire.arg(payload, :text),
               by: by
             }),
           {:ok, version, _events} <- MaybeCommentOnCard.dispatch(cmd),
           do: Wire.once_read(cmd.card_id, version, %{comment_id: cmd.comment_id})

    {:reply, Wire.reply(reply), state}
  end
end
