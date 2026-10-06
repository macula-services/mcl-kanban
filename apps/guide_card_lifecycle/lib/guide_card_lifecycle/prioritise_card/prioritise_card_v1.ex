defmodule GuideCardLifecycle.PrioritiseCard.PrioritiseCardV1 do
  # Command: a rank on the one scale across all boards (lower is claimed
  # first) and the rationale for it. The prioritiser must say why; the owner
  # may leave it empty.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, CardText, IssueRef}

  @max_rank 1_000_000

  @enforce_keys [:card_id, :rank, :by]
  defstruct [:card_id, :rank, :rationale, :by]

  @impl true
  def command_type, do: :prioritise_card

  @impl true
  def new(%{card_id: id, rank: rank, by: %Actor{} = by} = params) do
    with {:ok, id} <- IssueRef.valid_card_id(id),
         {:ok, rank} <- rank(rank),
         {:ok, rationale} <- rationale(Map.get(params, :rationale), by),
         do: {:ok, %__MODULE__{card_id: id, rank: rank, rationale: rationale, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  defp rank(rank) when is_integer(rank) and rank >= 0 and rank <= @max_rank, do: {:ok, rank}
  defp rank(_), do: {:error, :invalid_rank}

  defp rationale(text, %Actor{kind: :owner}), do: CardText.optional(text, 500, :invalid_rationale)
  defp rationale(text, %Actor{}), do: CardText.required(text, 500, :rationale_required)

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
