defmodule GuideCardLifecycle.WithdrawCard.WithdrawCardV1 do
  # Command: take a card off the board without it being done.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, CardText, IssueRef}

  @enforce_keys [:card_id, :by]
  defstruct [:card_id, :reason, :by]

  @impl true
  def command_type, do: :withdraw_card

  @impl true
  def new(%{card_id: id, by: %Actor{} = by} = params) do
    with {:ok, id} <- IssueRef.valid_card_id(id),
         {:ok, text} <- CardText.optional(Map.get(params, :reason), 500, :invalid_reason),
         do: {:ok, %__MODULE__{card_id: id, reason: text, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
