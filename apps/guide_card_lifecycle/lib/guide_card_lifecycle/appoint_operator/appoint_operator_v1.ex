defmodule GuideCardLifecycle.AppointOperator.AppointOperatorV1 do
  # Command: appoint the operator of a crew, an agent already enlisted in that
  # crew. The new one replaces the one sitting (#28).
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AgentName
  alias GuideCardLifecycle.CrewName

  @enforce_keys [:crew, :name, :by]
  defstruct [:crew, :name, :by]

  @impl true
  def command_type, do: :appoint_operator

  @impl true
  def new(%{crew: crew, name: name, by: %Actor{} = by}) do
    with {:ok, crew} <- CrewName.name(crew),
         {:ok, name} <- AgentName.name(name) do
      {:ok, %__MODULE__{crew: crew, name: name, by: by}}
    end
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
