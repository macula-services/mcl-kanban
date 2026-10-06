defmodule GuideCardLifecycle.EnlistAgent.MaybeEnlistAgent do
  # Handler: the supervisor or the owner enlists. A node id is enlisted once,
  # a name is taken once (case-insensitive).
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewState
  alias GuideCardLifecycle.EnlistAgent.{AgentEnlistedV1, EnlistAgentV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(EnlistAgentV1, payload))

  def handle(%CrewState{} = crew, %EnlistAgentV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      Map.has_key?(crew.agents, cmd.node_id) -> {:error, :already_enlisted}
      CrewState.node_id_of(crew, cmd.name) != nil -> {:error, :name_taken}
      true -> {:ok, [AgentEnlistedV1.from_command(cmd)]}
    end
  end

  def dispatch(%EnlistAgentV1{} = cmd) do
    :evoq_command.new(
      :enlist_agent,
      CrewAggregate,
      CrewAggregate.stream_id(),
      EnlistAgentV1.to_map(cmd)
    )
    |> :evoq_router.dispatch()
  end
end
