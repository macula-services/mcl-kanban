defmodule GuideCardLifecycle.CommentOnCard.CommentOnCardV1 do
  # Command: a comment on a card, for coordination (handoffs, blockers,
  # "picked this up"). The comment id is minted here: 32 hex digits.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, CardText, IssueRef}

  @enforce_keys [:card_id, :comment_id, :text, :by]
  defstruct [:card_id, :comment_id, :text, :by]

  @impl true
  def command_type, do: :comment_on_card

  @impl true
  def new(%{card_id: id, text: text, by: %Actor{} = by}) do
    with {:ok, id} <- IssueRef.valid_card_id(id),
         {:ok, text} <- CardText.required(text, 4000, :text_required),
         do: {:ok, %__MODULE__{card_id: id, comment_id: mint(), text: text, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  defp mint, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
