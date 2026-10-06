defmodule GuideCardLifecycle.DischargeAgent.DischargeAgentV1 do
  # Command: discharge an agent by name. Its node id stops acting on the board at once.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AgentName

  @enforce_keys [:name, :by]
  defstruct [:name, :by]

  @impl true
  def command_type, do: :discharge_agent

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
