defmodule GuideCardLifecycle.UntagCard.UntagCardV1 do
  # Command: Only a tag the card holds.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, CardTag, IssueRef}

  @enforce_keys [:card_id, :tag, :by]
  defstruct [:card_id, :tag, :by]

  @impl true
  def command_type, do: :untag_card

  @impl true
  def new(%{card_id: id, tag: tag, by: %Actor{} = by}) do
    with {:ok, id} <- IssueRef.valid_card_id(id),
         {:ok, tag} <- CardTag.tag(tag),
         do: {:ok, %__MODULE__{card_id: id, tag: tag, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
