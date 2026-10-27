defmodule GuideCardLifecycle.EnlistAgent.MaybeEnlistAgent do
  # Handler: the owner, or the operator of the crew being enlisted into (#28).
  # A node id is enlisted once, a name is taken once (case-insensitive).
  #
  # The crew a command names is a KEY (#40 option b): the owner and an operator
  # both submit it -- a bare name for a crew the board's owner made, a 64-hex
  # `crew_id` for one the realm admitted. It is never resolved from a name, so
  # the roster holds the very key the caller named.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewState
  alias GuideCardLifecycle.EnlistAgent.{AgentEnlistedV1, EnlistAgentV1}

  def handle_payload(state, payload), do: handle(state, struct(EnlistAgentV1, payload))

  def handle(%CrewState{} = crew, %EnlistAgentV1{} = cmd), do: listed(crew, cmd)

  defp listed(crew, cmd) do
    cond do
      not Actor.commands_crew?(cmd.by, cmd.crew) -> {:error, :not_permitted}
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
