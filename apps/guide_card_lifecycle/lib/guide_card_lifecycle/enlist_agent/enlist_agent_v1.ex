defmodule GuideCardLifecycle.EnlistAgent.EnlistAgentV1 do
  # Command: enlist an agent by name and node id. The node id is the one the
  # agent's MACULA_MCP_IDENTITY key signs with.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AgentName

  @enforce_keys [:name, :node_id, :by]
  defstruct [:name, :node_id, :by]

  @impl true
  def command_type, do: :enlist_agent

  @impl true
  def new(%{name: name, node_id: node_id, by: %Actor{} = by}) do
    with {:ok, name} <- AgentName.name(name),
         {:ok, node_id} <- AgentName.node_id(node_id) do
      {:ok, %__MODULE__{name: name, node_id: node_id, by: by}}
    end
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
