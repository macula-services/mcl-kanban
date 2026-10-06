defmodule GuideCardLifecycle.DeferPackage.DeferPackageV1 do
  # Command: pause a work package, with a reason: its cards are not handed out.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, CardText}

  @enforce_keys [:package_id, :by]
  defstruct [:package_id, :reason, :by]

  @impl true
  def command_type, do: :defer_package

  @impl true
  def new(%{package_id: id, reason: text, by: %Actor{} = by}) when is_binary(id) do
    with {:ok, text} <- CardText.required(text, 500, :reason_required),
         do: {:ok, %__MODULE__{package_id: id, reason: text, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
