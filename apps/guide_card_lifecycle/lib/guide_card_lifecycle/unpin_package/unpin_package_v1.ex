defmodule GuideCardLifecycle.UnpinPackage.UnpinPackageV1 do
  # Command: let the prioritiser rank the package again.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.Actor

  @enforce_keys [:package_id, :by]
  defstruct [:package_id, :by]

  @impl true
  def command_type, do: :unpin_package

  @impl true
  def new(%{package_id: id, by: %Actor{} = by}) when is_binary(id),
    do: {:ok, %__MODULE__{package_id: id, by: by}}

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
