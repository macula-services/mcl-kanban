defmodule GuideCardLifecycle.UnpinCard.UnpinCardV1 do
  # Command: let the prioritiser rank the card again.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, IssueRef}

  @enforce_keys [:card_id, :by]
  defstruct [:card_id, :by]

  @impl true
  def command_type, do: :unpin_card

  @impl true
  def new(%{card_id: id, by: %Actor{} = by}) do
    with {:ok, id} <- IssueRef.valid_card_id(id), do: {:ok, %__MODULE__{card_id: id, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
