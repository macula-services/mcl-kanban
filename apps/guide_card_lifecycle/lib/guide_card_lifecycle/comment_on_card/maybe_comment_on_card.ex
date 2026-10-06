defmodule GuideCardLifecycle.CommentOnCard.MaybeCommentOnCard do
  # Handler: any agent or the owner comments. Comments are append-only and
  # never mirrored to GitHub.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState}
  alias GuideCardLifecycle.CommentOnCard.{CardCommentedV1, CommentOnCardV1}

  @who [:agent, :owner]

  def handle_payload(state, payload), do: handle(state, struct(CommentOnCardV1, payload))

  def handle(%CardState{} = card, %CommentOnCardV1{} = cmd) do
    case Actor.allowed?(cmd.by, @who) do
      true ->
        {:ok,
         [CardCommentedV1.new(cmd, card.status, %{comment_id: cmd.comment_id, text: cmd.text})]}

      false ->
        {:error, :not_permitted}
    end
  end

  def dispatch(%CommentOnCardV1{} = cmd),
    do: CardAggregate.dispatch(:comment_on_card, cmd.card_id, CommentOnCardV1.to_map(cmd))
end
