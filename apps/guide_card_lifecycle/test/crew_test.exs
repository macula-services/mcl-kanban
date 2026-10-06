defmodule GuideCardLifecycle.CrewTest do
  # The crew roster: enlisting, discharging and the two appointments. The
  # crew always has exactly one supervisor once founded; the prioritiser is
  # optional.
  use ExUnit.Case, async: true

  import GuideCardLifecycle.TestCrew

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AdoptGoal.{AdoptGoalV1, MaybeAdoptGoal}
  alias GuideCardLifecycle.AppointPrioritiser.{AppointPrioritiserV1, MaybeAppointPrioritiser}
  alias GuideCardLifecycle.AppointSupervisor.{AppointSupervisorV1, MaybeAppointSupervisor}
  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewState
  alias GuideCardLifecycle.DischargeAgent.{DischargeAgentV1, MaybeDischargeAgent}
  alias GuideCardLifecycle.EnlistAgent.{EnlistAgentV1, MaybeEnlistAgent}

  defp enlist(name, node_hex, by) do
    {:ok, cmd} = EnlistAgentV1.new(%{name: name, node_id: node_hex, by: by})
    cmd
  end

  describe "enlist_agent" do
    test "the supervisor enlists an agent by name and node id" do
      cmd = enlist("dan", hex("dan"), actor("ada"))

      assert {:ok, [%{event_type: "agent_enlisted_v1", name: "dan", node_id: node} = event]} =
               MaybeEnlistAgent.handle(crew(), cmd)

      assert node == hex("dan")
      assert event.by == "ada"
      assert is_integer(event.at)
    end

    test "the owner enlists, so the first agent can be enlisted at all" do
      cmd = enlist("ada", hex("ada"), Actor.owner())

      assert {:ok, [%{by: "owner", by_kind: "owner"}]} =
               MaybeEnlistAgent.handle(CrewState.new(), cmd)
    end

    test "a plain agent or the prioritiser may not enlist" do
      for name <- ~w(bob pia) do
        cmd = enlist("dan", hex("dan"), actor(name))
        assert {:error, :not_permitted} = MaybeEnlistAgent.handle(crew(), cmd)
      end
    end

    test "a node id is enlisted once, and a name is taken once" do
      assert {:error, :already_enlisted} =
               MaybeEnlistAgent.handle(crew(), enlist("dan", hex("bob"), actor("ada")))

      assert {:error, :name_taken} =
               MaybeEnlistAgent.handle(crew(), enlist("BOB", hex("dan"), actor("ada")))
    end

    test "the command refuses a malformed node id or name, and the reserved name owner" do
      assert {:error, :invalid_node_id} =
               EnlistAgentV1.new(%{name: "dan", node_id: "abc", by: actor("ada")})

      assert {:error, :invalid_node_id} =
               EnlistAgentV1.new(%{
                 name: "dan",
                 node_id: String.duplicate("z", 64),
                 by: actor("ada")
               })

      assert {:error, :invalid_name} =
               EnlistAgentV1.new(%{name: "", node_id: hex("dan"), by: actor("ada")})

      assert {:error, :invalid_name} =
               EnlistAgentV1.new(%{name: "has space", node_id: hex("dan"), by: actor("ada")})

      assert {:error, :name_reserved} =
               EnlistAgentV1.new(%{name: "Owner", node_id: hex("dan"), by: actor("ada")})
    end

    test "an upper-case node id is stored lower-case" do
      {:ok, cmd} =
        EnlistAgentV1.new(%{name: "dan", node_id: String.upcase(hex("dan")), by: actor("ada")})

      assert cmd.node_id == hex("dan")
    end
  end

  describe "discharge_agent" do
    test "the supervisor discharges an agent by name" do
      {:ok, cmd} = DischargeAgentV1.new(%{name: "bob", by: actor("ada")})

      assert {:ok, [%{event_type: "agent_discharged_v1", name: "bob", node_id: node}]} =
               MaybeDischargeAgent.handle(crew(), cmd)

      assert node == hex("bob")
    end

    test "discharging the supervisor is refused" do
      {:ok, cmd} = DischargeAgentV1.new(%{name: "ada", by: Actor.owner()})
      assert {:error, :supervisor_required} = MaybeDischargeAgent.handle(crew(), cmd)
    end

    test "discharging the prioritiser leaves the crew without one" do
      {:ok, cmd} = DischargeAgentV1.new(%{name: "pia", by: actor("ada")})
      {:ok, events} = MaybeDischargeAgent.handle(crew(), cmd)
      after_ = Enum.reduce(events, crew(), &CrewState.apply_event(&2, &1))
      assert after_.prioritiser == nil
      assert {:error, :not_enlisted} = Actor.from_crew(after_, node_id("pia"))
    end

    test "an unknown name is refused, and a plain agent may not discharge" do
      {:ok, unknown} = DischargeAgentV1.new(%{name: "zed", by: actor("ada")})
      assert {:error, :unknown_agent} = MaybeDischargeAgent.handle(crew(), unknown)

      {:ok, by_bob} = DischargeAgentV1.new(%{name: "cyd", by: actor("bob")})
      assert {:error, :not_permitted} = MaybeDischargeAgent.handle(crew(), by_bob)
    end
  end

  describe "appointments" do
    test "only the owner appoints the supervisor, and the new one replaces the old" do
      {:ok, by_ada} = AppointSupervisorV1.new(%{name: "bob", by: actor("ada")})
      assert {:error, :not_permitted} = MaybeAppointSupervisor.handle(crew(), by_ada)

      {:ok, cmd} = AppointSupervisorV1.new(%{name: "bob", by: Actor.owner()})
      {:ok, events} = MaybeAppointSupervisor.handle(crew(), cmd)
      after_ = Enum.reduce(events, crew(), &CrewState.apply_event(&2, &1))

      assert after_.supervisor == hex("bob")
      assert {:ok, %Actor{roles: [:agent]}} = Actor.from_crew(after_, node_id("ada"))
      {:ok, bob} = Actor.from_crew(after_, node_id("bob"))
      assert :supervisor in bob.roles
    end

    test "only an enlisted agent can be appointed" do
      {:ok, cmd} = AppointSupervisorV1.new(%{name: "zed", by: Actor.owner()})
      assert {:error, :unknown_agent} = MaybeAppointSupervisor.handle(crew(), cmd)

      {:ok, prio} = AppointPrioritiserV1.new(%{name: "zed", by: Actor.owner()})
      assert {:error, :unknown_agent} = MaybeAppointPrioritiser.handle(crew(), prio)
    end

    test "re-appointing the sitting supervisor or prioritiser is refused" do
      {:ok, sup} = AppointSupervisorV1.new(%{name: "ada", by: Actor.owner()})
      assert {:error, :already_appointed} = MaybeAppointSupervisor.handle(crew(), sup)

      {:ok, prio} = AppointPrioritiserV1.new(%{name: "pia", by: Actor.owner()})
      assert {:error, :already_appointed} = MaybeAppointPrioritiser.handle(crew(), prio)
    end

    test "only the owner appoints the prioritiser" do
      {:ok, cmd} = AppointPrioritiserV1.new(%{name: "bob", by: actor("ada")})
      assert {:error, :not_permitted} = MaybeAppointPrioritiser.handle(crew(), cmd)

      {:ok, by_owner} = AppointPrioritiserV1.new(%{name: "bob", by: Actor.owner()})

      assert {:ok, [%{event_type: "prioritiser_appointed_v1", name: "bob"}]} =
               MaybeAppointPrioritiser.handle(crew(), by_owner)
    end
  end

  test "the aggregate routes each crew command to its desk and refuses others" do
    {:ok, cmd} = EnlistAgentV1.new(%{name: "dan", node_id: hex("dan"), by: actor("ada")})

    assert {:ok, [%{event_type: "agent_enlisted_v1"}]} =
             CrewAggregate.execute(crew(), EnlistAgentV1.to_payload(cmd))

    assert {:error, :unknown_command} = CrewAggregate.execute(crew(), %{command_type: :bogus})
  end

  test "the crew has one fixed stream id that reckon-db accepts" do
    assert :ok = :reckon_gater_stream_id.validate(CrewAggregate.stream_id())
  end

  describe "adopt_goal (#18)" do
    defp goal(by, packages \\ ["example-org/widget#1"], text \\ "So the crew ships the board") do
      AdoptGoalV1.new(%{goal: text, packages: packages, by: by})
    end

    test "the supervisor or the owner adopts the crew's one goal: a sentence and its packages" do
      {:ok, cmd} = goal(actor("ada"), ["example-org/widget#1", "example-org/gadget#2"])

      assert {:ok, [%{event_type: "goal_adopted_v1", goal: "So the crew ships the board"} = e]} =
               MaybeAdoptGoal.handle(crew(), cmd)

      assert e.packages == ["example-org/widget#1", "example-org/gadget#2"]
      adopted = CrewState.apply_event(crew(), e)
      assert adopted.goal == %{goal: "So the crew ships the board", packages: e.packages, by: "ada", at: e.at}

      {:ok, by_owner} = goal(Actor.owner())
      assert {:ok, [_]} = MaybeAdoptGoal.handle(crew(), by_owner)
    end

    test "nobody else adopts a goal" do
      {:ok, by_bob} = goal(actor("bob"))
      assert {:error, :not_permitted} = MaybeAdoptGoal.handle(crew(), by_bob)
      {:ok, by_pia} = goal(actor("pia"))
      assert {:error, :not_permitted} = MaybeAdoptGoal.handle(crew(), by_pia)
    end

    test "a goal is one sentence and one or two packages" do
      assert {:error, :goal_required} = goal(actor("ada"), ["example-org/widget#1"], " ")
      assert {:error, :invalid_goal_packages} = goal(actor("ada"), [])

      assert {:error, :invalid_goal_packages} =
               goal(actor("ada"), ["example-org/a#1", "example-org/b#2", "example-org/c#3"])

      assert {:error, :invalid_issue_ref} = goal(actor("ada"), ["not a ref"])
    end
  end
end
