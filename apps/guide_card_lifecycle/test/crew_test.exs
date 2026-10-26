defmodule GuideCardLifecycle.CrewTest do
  # The crew roster: enlisting, discharging and the two appointments. The
  # crew always has exactly one supervisor once founded; the prioritiser is
  # optional.
  use ExUnit.Case, async: true

  import GuideCardLifecycle.TestCrew

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AdoptGoal.{AdoptGoalV1, MaybeAdoptGoal}
  alias GuideCardLifecycle.AppointOperator.{AppointOperatorV1, MaybeAppointOperator}
  alias GuideCardLifecycle.AppointPrioritiser.{AppointPrioritiserV1, MaybeAppointPrioritiser}
  alias GuideCardLifecycle.AppointSupervisor.{AppointSupervisorV1, MaybeAppointSupervisor}
  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewState
  alias GuideCardLifecycle.DischargeAgent.{DischargeAgentV1, MaybeDischargeAgent}
  alias GuideCardLifecycle.EnlistAgent.{EnlistAgentV1, MaybeEnlistAgent}

  defp enlist(name, node_hex, by, crew \\ "home") do
    {:ok, cmd} = EnlistAgentV1.new(%{name: name, node_id: node_hex, crew: crew, by: by})
    cmd
  end

  describe "enlist_agent" do
    test "a crew's operator enlists an agent into it, and the event names the crew" do
      cmd = enlist("dan", hex("dan"), operator_actor("bob"))

      assert {:ok,
              [
                %{event_type: "agent_enlisted_v1", name: "dan", node_id: node, crew: "home"} =
                  event
              ]} =
               MaybeEnlistAgent.handle(crews(), cmd)

      assert node == hex("dan")
      assert event.by == "bob"
      assert is_integer(event.at)
    end

    test "the owner enlists into any crew, so a second crew can be founded at all" do
      assert {:ok, [%{by: "owner", by_kind: "owner", crew: "home"}]} =
               MaybeEnlistAgent.handle(CrewState.new(), enlist("ada", hex("ada"), Actor.owner()))

      assert {:ok, [%{crew: "night"}]} =
               MaybeEnlistAgent.handle(
                 CrewState.new(),
                 enlist("eve", hex("eve"), Actor.owner(), "night")
               )
    end

    test "a crew's operator may not enlist into another crew" do
      assert {:error, :not_permitted} =
               MaybeEnlistAgent.handle(
                 crews(),
                 enlist("dan", hex("dan"), operator_actor("bob"), "night")
               )
    end

    test "nobody else enlists: not the supervisor, not the prioritiser, not a plain agent" do
      for name <- ~w(ada pia bob cyd) do
        cmd = enlist("dan", hex("dan"), actor(name))
        assert {:error, :not_permitted} = MaybeEnlistAgent.handle(crew(), cmd)
      end
    end

    test "a node id is enlisted once, and a name is taken once" do
      assert {:error, :already_enlisted} =
               MaybeEnlistAgent.handle(
                 crews(),
                 enlist("dan", hex("bob"), operator_actor("bob"))
               )

      assert {:error, :name_taken} =
               MaybeEnlistAgent.handle(
                 crews(),
                 enlist("BOB", hex("dan"), operator_actor("bob"))
               )
    end

    test "the command refuses a malformed node id, name or crew, and the reserved name owner" do
      assert {:error, :invalid_node_id} =
               EnlistAgentV1.new(%{name: "dan", node_id: "abc", crew: "home", by: actor("ada")})

      assert {:error, :invalid_node_id} =
               EnlistAgentV1.new(%{
                 name: "dan",
                 node_id: String.duplicate("z", 64),
                 crew: "home",
                 by: actor("ada")
               })

      assert {:error, :invalid_name} =
               EnlistAgentV1.new(%{name: "", node_id: hex("dan"), crew: "home", by: actor("ada")})

      assert {:error, :invalid_name} =
               EnlistAgentV1.new(%{
                 name: "has space",
                 node_id: hex("dan"),
                 crew: "home",
                 by: actor("ada")
               })

      assert {:error, :name_reserved} =
               EnlistAgentV1.new(%{
                 name: "Owner",
                 node_id: hex("dan"),
                 crew: "home",
                 by: actor("ada")
               })

      assert {:error, :invalid_crew} =
               EnlistAgentV1.new(%{
                 name: "dan",
                 node_id: hex("dan"),
                 crew: "not a crew",
                 by: actor("ada")
               })

      assert {:error, :missing_required_fields} =
               EnlistAgentV1.new(%{name: "dan", node_id: hex("dan"), by: actor("ada")})
    end

    test "an upper-case node id is stored lower-case" do
      {:ok, cmd} =
        EnlistAgentV1.new(%{
          name: "dan",
          node_id: String.upcase(hex("dan")),
          crew: "home",
          by: actor("ada")
        })

      assert cmd.node_id == hex("dan")
    end
  end

  describe "discharge_agent" do
    test "a crew's operator discharges an agent of it" do
      {:ok, cmd} = DischargeAgentV1.new(%{name: "cyd", by: operator_actor("bob")})

      assert {:ok, [%{event_type: "agent_discharged_v1", name: "cyd", node_id: node}]} =
               MaybeDischargeAgent.handle(crews(), cmd)

      assert node == hex("cyd")
    end

    test "an operator may not discharge an agent of another crew" do
      {:ok, cmd} = DischargeAgentV1.new(%{name: "bob", by: operator_actor("eve")})
      assert {:error, :not_permitted} = MaybeDischargeAgent.handle(crews(), cmd)
    end

    test "the owner discharges in any crew" do
      {:ok, cmd} = DischargeAgentV1.new(%{name: "bob", by: Actor.owner()})

      assert {:ok, [%{event_type: "agent_discharged_v1"}]} =
               MaybeDischargeAgent.handle(crews(), cmd)
    end

    test "discharging the supervisor is refused" do
      {:ok, cmd} = DischargeAgentV1.new(%{name: "ada", by: Actor.owner()})
      assert {:error, :supervisor_required} = MaybeDischargeAgent.handle(crew(), cmd)
    end

    test "discharging the prioritiser leaves the crew without one" do
      {:ok, cmd} = DischargeAgentV1.new(%{name: "pia", by: Actor.owner()})
      {:ok, events} = MaybeDischargeAgent.handle(crew(), cmd)
      after_ = Enum.reduce(events, crew(), &CrewState.apply_event(&2, &1))
      assert after_.prioritiser == nil
      assert {:error, :not_enlisted} = Actor.from_crew(after_, node_id("pia"))
    end

    test "discharging a crew's operator leaves that crew with none" do
      {:ok, cmd} = DischargeAgentV1.new(%{name: "eve", by: Actor.owner()})
      {:ok, events} = MaybeDischargeAgent.handle(crews(), cmd)
      after_ = Enum.reduce(events, crews(), &CrewState.apply_event(&2, &1))

      assert CrewState.operator_of(after_, "night") == nil
      assert CrewState.operator_of(after_, "home") == hex("bob")
      assert {:error, :not_enlisted} = Actor.from_crew(after_, node_id("eve"))
    end

    test "an unknown name is refused, and a plain agent may not discharge" do
      {:ok, unknown} = DischargeAgentV1.new(%{name: "zed", by: Actor.owner()})
      assert {:error, :unknown_agent} = MaybeDischargeAgent.handle(crew(), unknown)

      {:ok, by_bob} = DischargeAgentV1.new(%{name: "cyd", by: actor("bob")})
      assert {:error, :not_permitted} = MaybeDischargeAgent.handle(crew(), by_bob)
    end
  end

  describe "appoint_operator (#28)" do
    defp appoint(crew, name, by) do
      {:ok, cmd} = AppointOperatorV1.new(%{crew: crew, name: name, by: by})
      cmd
    end

    defp appoint!(crew, name, by) do
      {:ok, events} = MaybeAppointOperator.handle(crews(), appoint(crew, name, by))
      Enum.reduce(events, crews(), &CrewState.apply_event(&2, &1))
    end

    test "only the owner appoints an operator" do
      assert {:error, :not_permitted} =
               MaybeAppointOperator.handle(crews(), appoint("home", "cyd", operator_actor("bob")))

      assert {:error, :not_permitted} =
               MaybeAppointOperator.handle(crews(), appoint("home", "cyd", actor("ada")))
    end

    test "the operator must be an agent enlisted in that very crew" do
      assert {:error, :unknown_agent} =
               MaybeAppointOperator.handle(crews(), appoint("home", "zed", Actor.owner()))

      assert {:error, :agent_in_another_crew} =
               MaybeAppointOperator.handle(crews(), appoint("night", "bob", Actor.owner()))
    end

    test "appointing the operator already sitting is refused" do
      assert {:error, :already_appointed} =
               MaybeAppointOperator.handle(crews(), appoint("home", "bob", Actor.owner()))
    end

    test "appointing another replaces the one sitting, and each runs only its own crew" do
      events = MaybeAppointOperator.handle(crews(), appoint("home", "cyd", Actor.owner()))
      {:ok, [%{event_type: "operator_appointed_v1", crew: "home", name: "cyd"} = event]} = events
      assert event.by == "owner"

      after_ = appoint!("home", "cyd", Actor.owner())
      assert CrewState.operator_of(after_, "home") == hex("cyd")
      assert {:ok, %Actor{roles: [:agent]}} = Actor.from_crew(after_, node_id("bob"))

      {:ok, cyd} = Actor.from_crew(after_, node_id("cyd"))
      assert :operator in cyd.roles
      assert Actor.commands_crew?(cyd, "home")
      refute Actor.commands_crew?(cyd, "night")
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
    {:ok, cmd} =
      EnlistAgentV1.new(%{
        name: "dan",
        node_id: hex("dan"),
        crew: "home",
        by: operator_actor("bob")
      })

    assert {:ok, [%{event_type: "agent_enlisted_v1"}]} =
             CrewAggregate.execute(crews(), EnlistAgentV1.to_payload(cmd))

    {:ok, appoint} = AppointOperatorV1.new(%{crew: "home", name: "cyd", by: Actor.owner()})

    assert {:ok, [%{event_type: "operator_appointed_v1"}]} =
             CrewAggregate.execute(crews(), AppointOperatorV1.to_payload(appoint))

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

      assert adopted.goal == %{
               goal: "So the crew ships the board",
               packages: e.packages,
               by: "ada",
               at: e.at
             }

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
