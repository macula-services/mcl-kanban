defmodule GuideCardLifecycle.CrewFactActorTest do
  # The realm's actor (mcl-kanban#40, R4): the board acts for the realm because
  # the realm signed a fact. So the realm must be able to do what admitting a
  # crew takes, and must be impossible for a caller to claim.
  use ExUnit.Case, async: true

  import GuideCardLifecycle.TestCrew

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AgentName
  alias GuideCardLifecycle.AppointOperator.{AppointOperatorV1, MaybeAppointOperator}
  alias GuideCardLifecycle.CrewState
  alias GuideCardLifecycle.DischargeAgent.{DischargeAgentV1, MaybeDischargeAgent}
  alias GuideCardLifecycle.EnlistAgent.{EnlistAgentV1, MaybeEnlistAgent}

  test "the realm commands every crew; an operator commands only its own" do
    assert Actor.commands_crew?(Actor.realm(), "home")
    assert Actor.commands_crew?(Actor.realm(), "a-crew-the-board-never-saw")
    assert Actor.commands_crew?(operator_actor("bob"), "home")
    refute Actor.commands_crew?(operator_actor("bob"), "night")
  end

  test "no payload makes a caller the realm, however it is worded" do
    payload = %{
      "by" => "realm",
      "kind" => "realm",
      "roles" => ["realm"],
      :caller => node_id("bob")
    }

    assert {:ok, %Actor{kind: :agent, name: "bob"}} = Actor.from_payload(crews(), payload)

    assert {:ok, %Actor{kind: :agent}} =
             Actor.from_payload(crews(), Map.put(payload, :caller, node_id("ada")))

    # the realm is not reachable through the caller path at all
    assert {:error, :not_enlisted} = Actor.from_crew(crews(), node_id("realm"))
    assert {:error, :no_caller} = Actor.from_crew(crews(), "realm")
  end

  test "an agent may not carry the realm's name, as it may not carry the owner's" do
    assert {:error, :name_reserved} = AgentName.name("realm")
    assert {:error, :name_reserved} = AgentName.name("Realm")
    assert {:error, :name_reserved} = AgentName.name("owner")
    assert {:ok, "realmish"} = AgentName.name("realmish")
  end

  test "the realm appoints a crew's operator, and an operator of another crew still cannot" do
    {:ok, [enlisted]} =
      MaybeEnlistAgent.handle(crews(), %EnlistAgentV1{
        name: "fay",
        node_id: hex("fay"),
        crew: "night",
        by: Actor.realm()
      })

    crew = CrewState.apply_event(crews(), enlisted)

    assert {:ok, [event]} =
             MaybeAppointOperator.handle(crew, %AppointOperatorV1{
               crew: "night",
               name: "fay",
               by: Actor.realm()
             })

    assert event.event_type == "operator_appointed_v1"
    assert event.crew == "night"
    assert event.name == "fay"

    refute Actor.commands_crew?(operator_actor("bob"), "night")

    assert {:error, :not_permitted} =
             MaybeAppointOperator.handle(crew, %AppointOperatorV1{
               crew: "night",
               name: "fay",
               by: operator_actor("bob")
             })
  end

  test "the realm enlists and discharges, which is what admitting and dropping a crew take" do
    assert {:ok, [enlisted]} =
             MaybeEnlistAgent.handle(crew(), %EnlistAgentV1{
               name: "newbie",
               node_id: hex("newbie"),
               crew: "night",
               by: Actor.realm()
             })

    assert enlisted.event_type == "agent_enlisted_v1"
    assert enlisted.by_kind == "realm"

    assert {:ok, [discharged]} =
             MaybeDischargeAgent.handle(crews(), %DischargeAgentV1{name: "eve", by: Actor.realm()})

    assert discharged.event_type == "agent_discharged_v1"

    # the same acts by an operator of another crew are refused
    assert {:error, :not_permitted} =
             MaybeDischargeAgent.handle(crews(), %DischargeAgentV1{name: "eve", by: actor("bob")})
  end

  test "a record of a realm act says so, and never reads as an agent's" do
    assert %{by: "realm", by_kind: "realm", by_node_id: nil} = Actor.record(Actor.realm())
    assert %{by_kind: "agent", by_node_id: bob} = Actor.record(actor("bob"))
    assert bob == hex("bob")
  end
end
