defmodule GuideCardLifecycle.FileCard.FileCardV1 do
  # Command: file a card into a work package, named by the package's issue
  # (owner/repo#n). A card may sit in a package of another repo.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, IssueRef}

  @enforce_keys [:card_id, :package_ref, :by]
  defstruct [:card_id, :package_ref, :by]

  @impl true
  def command_type, do: :file_card

  @impl true
  def new(%{card_id: id, package_ref: ref, by: %Actor{} = by}) do
    with {:ok, id} <- IssueRef.valid_card_id(id),
         {:ok, %{issue_ref: ref}} <- IssueRef.parse(ref),
         do: {:ok, %__MODULE__{card_id: id, package_ref: ref, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
