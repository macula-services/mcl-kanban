defmodule GuideCardLifecycle.BlockCard.BlockCardV1 do
  # Command: block a card, with a reason (usually a linked card).
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, CardText, IssueRef}

  @enforce_keys [:card_id, :by]
  defstruct [:card_id, :reason, :by]

  @impl true
  def command_type, do: :block_card

  @impl true
  def new(%{card_id: id, reason: text, by: %Actor{} = by}) do
    with {:ok, id} <- IssueRef.valid_card_id(id),
         {:ok, text} <- CardText.required(text, 500, :reason_required),
         do: {:ok, %__MODULE__{card_id: id, reason: text, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
