defmodule GuideCardLifecycle.AppointSupervisor.AppointSupervisorV1 do
  # Command: appoint the supervisor, an enlisted agent. The new one replaces the old.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AgentName

  @enforce_keys [:name, :by]
  defstruct [:name, :by]

  @impl true
  def command_type, do: :appoint_supervisor

  @impl true
  def new(%{name: name, by: %Actor{} = by}) do
    with {:ok, name} <- AgentName.name(name), do: {:ok, %__MODULE__{name: name, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
