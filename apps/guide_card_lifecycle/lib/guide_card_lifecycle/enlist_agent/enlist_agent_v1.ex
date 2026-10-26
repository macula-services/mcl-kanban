defmodule GuideCardLifecycle.EnlistAgent.EnlistAgentV1 do
  # Command: enlist an agent by name, node id and crew. The node id is the one
  # the agent's MACULA_MCP_IDENTITY key signs with; the crew is the one its
  # operator may command it in (#28).
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AgentName
  alias GuideCardLifecycle.CrewName

  @enforce_keys [:name, :node_id, :crew, :by]
  defstruct [:name, :node_id, :crew, :by]

  @impl true
  def command_type, do: :enlist_agent

  @impl true
  def new(%{name: name, node_id: node_id, crew: crew, by: %Actor{} = by}) do
    with {:ok, name} <- AgentName.name(name),
         {:ok, node_id} <- AgentName.node_id(node_id),
         {:ok, crew} <- CrewName.name(crew) do
      {:ok, %__MODULE__{name: name, node_id: node_id, crew: crew, by: by}}
    end
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
