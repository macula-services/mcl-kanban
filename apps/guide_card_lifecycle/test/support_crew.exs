defmodule GuideCardLifecycle.TestCrew do
  # A crew built from events, the way the aggregate builds it: ada is the
  # supervisor, pia the prioritiser, bob and cyd plain agents. Node ids are
  # synthetic (this repository is public).
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CrewState

  def node_id(name), do: :crypto.hash(:sha256, "synthetic node " <> name)
  def hex(name), do: Base.encode16(node_id(name), case: :lower)

  def crew do
    [
      %{event_type: "agent_enlisted_v1", node_id: hex("ada"), name: "ada"},
      %{event_type: "agent_enlisted_v1", node_id: hex("pia"), name: "pia"},
      %{event_type: "agent_enlisted_v1", node_id: hex("bob"), name: "bob"},
      %{event_type: "agent_enlisted_v1", node_id: hex("cyd"), name: "cyd"},
      %{event_type: "supervisor_appointed_v1", node_id: hex("ada"), name: "ada"},
      %{event_type: "prioritiser_appointed_v1", node_id: hex("pia"), name: "pia"}
    ]
    |> Enum.reduce(CrewState.new(), &CrewState.apply_event(&2, &1))
  end

  def actor(name) do
    {:ok, actor} = Actor.from_crew(crew(), node_id(name))
    actor
  end
end
