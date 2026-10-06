defmodule GuideCardLifecycle.EnlistAgent.AgentEnlistedV1 do
  # Event: agent_enlisted_v1.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.EnlistAgent.EnlistAgentV1

  def event_type, do: "agent_enlisted_v1"

  def from_command(%EnlistAgentV1{} = cmd) do
    Map.merge(Actor.record(cmd.by), %{
      event_type: event_type(),
      node_id: cmd.node_id,
      name: cmd.name,
      at: System.system_time(:millisecond)
    })
  end
end
