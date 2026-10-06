defmodule GuideCardLifecycle.ReclassifyCard.ReclassifyCardV1 do
  # Command: a new kind (bug, slice or ui), and so a new colour.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, CardKind, IssueRef}

  @enforce_keys [:card_id, :kind, :by]
  defstruct [:card_id, :kind, :by]

  @impl true
  def command_type, do: :reclassify_card

  @impl true
  def new(%{card_id: id, kind: kind, by: %Actor{} = by}) do
    with {:ok, id} <- IssueRef.valid_card_id(id),
         {:ok, kind} <- CardKind.kind(kind),
         do: {:ok, %__MODULE__{card_id: id, kind: kind, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
