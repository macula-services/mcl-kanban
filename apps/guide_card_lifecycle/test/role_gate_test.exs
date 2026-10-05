defmodule GuideCardLifecycle.RoleGateTest do
  # The role gate: who a call acts as, and with which roles. A mesh caller's
  # roles come ONLY from the crew, looked up by the node id that signed the
  # call. Nothing in a payload can name a role, and no mesh caller is ever
  # the owner.
  use ExUnit.Case, async: true

  import GuideCardLifecycle.TestCrew

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CrewState

  test "an enlisted caller acts as its own name, with the roles the crew gives it" do
    assert {:ok, %Actor{kind: :agent, name: "ada", roles: roles}} =
             Actor.from_crew(crew(), node_id("ada"))

    assert Enum.sort(roles) == [:agent, :supervisor]

    assert {:ok, %Actor{name: "pia", roles: pia}} = Actor.from_crew(crew(), node_id("pia"))
    assert Enum.sort(pia) == [:agent, :prioritiser]

    assert {:ok, %Actor{name: "bob", roles: [:agent], node_id: bob}} =
             Actor.from_crew(crew(), node_id("bob"))

    assert bob == hex("bob")
  end

  test "a caller the crew does not know is refused" do
    assert {:error, :not_enlisted} = Actor.from_crew(crew(), node_id("mallory"))
  end

  test "a call without a signed caller is refused" do
    assert {:error, :no_caller} = Actor.from_crew(crew(), nil)
    assert {:error, :no_caller} = Actor.from_crew(crew(), :undefined)
  end

  test "a caller given as hex text is not a signed caller" do
    # macula delivers the signer as 32 raw bytes. Text is something a payload
    # could carry, so it is never taken for the signer.
    assert {:error, :no_caller} = Actor.from_crew(crew(), hex("ada"))
    assert {:error, :no_caller} = Actor.from_crew(crew(), {:text, hex("ada")})
  end

  test "the caller comes from the signed field, never from a name or role in the payload" do
    payload = %{
      :caller => node_id("bob"),
      {:text, "name"} => {:text, "ada"},
      {:text, "role"} => {:text, "owner"},
      {:text, "roles"} => [{:text, "supervisor"}]
    }

    assert {:ok, %Actor{name: "bob", roles: [:agent]}} = Actor.from_payload(crew(), payload)
  end

  test "a payload that only names a caller as text has no caller" do
    payload = %{{:text, "caller"} => {:text, hex("ada")}}
    assert {:error, :no_caller} = Actor.from_payload(crew(), payload)
  end

  test "a discharged agent is refused" do
    crew =
      CrewState.apply_event(crew(), %{
        event_type: "agent_discharged_v1",
        node_id: hex("bob"),
        name: "bob"
      })

    assert {:error, :not_enlisted} = Actor.from_crew(crew, node_id("bob"))
  end

  test "no mesh caller is ever the owner" do
    for name <- ~w(ada pia bob cyd) do
      {:ok, actor} = Actor.from_crew(crew(), node_id(name))
      assert actor.kind == :agent
      refute :owner in actor.roles
    end
  end

  test "the owner is its own actor, recorded as such" do
    owner = Actor.owner()
    assert owner.kind == :owner
    assert owner.name == "owner"
    assert owner.node_id == nil
    assert owner.roles == [:owner]
  end

  test "allowed? checks the named roles, and the owner only where named" do
    ada = actor("ada")
    bob = actor("bob")

    assert Actor.allowed?(ada, [:supervisor])
    refute Actor.allowed?(bob, [:supervisor, :prioritiser])
    assert Actor.allowed?(bob, [:agent])
    assert Actor.allowed?(Actor.owner(), [:supervisor, :owner])
    refute Actor.allowed?(Actor.owner(), [:agent])
  end

  test "an actor's record names who acted and how" do
    assert %{by: "bob", by_kind: "agent", by_node_id: node} = Actor.record(actor("bob"))
    assert node == hex("bob")
    assert %{by: "owner", by_kind: "owner", by_node_id: nil} = Actor.record(Actor.owner())
  end
end
