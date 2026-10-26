defmodule GuideCardLifecycle.TestCrew do
  # A crew built from events, the way the aggregate builds it: ada is the
  # supervisor, pia the prioritiser, bob and cyd plain agents, all of them in
  # the home crew (their events name no crew, the way the ones from before
  # #28 read). Node ids are synthetic (this repository is public).
  #
  # crews/0 adds what #28 brought: a second crew, night, with eve in it as its
  # operator, and bob as the operator of home. bob the operator is a different
  # actor from bob the plain agent, so a test says which one it means.
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

  def crews do
    [
      %{event_type: "agent_enlisted_v1", node_id: hex("eve"), name: "eve", crew: "night"},
      %{event_type: "operator_appointed_v1", crew: "home", node_id: hex("bob"), name: "bob"},
      %{event_type: "operator_appointed_v1", crew: "night", node_id: hex("eve"), name: "eve"}
    ]
    |> Enum.reduce(crew(), &CrewState.apply_event(&2, &1))
  end

  def actor(name) do
    {:ok, actor} = Actor.from_crew(crew(), node_id(name))
    actor
  end

  @doc "A caller as crews/0 knows it: bob and eve are their crews' operators here."
  def operator_actor(name) do
    {:ok, actor} = Actor.from_crew(crews(), node_id(name))
    actor
  end
end
