defmodule MclKanban.CrewFactsOverMeshTest do
  # The realm's crew facts, end to end on a real store (#40): what the board
  # does with a fact it believes -- appoint, replace, drop -- and with one it
  # does not: another key's, another fact's topic, or a seq it has already
  # taken. Node ids are synthetic (this repository is public).
  #
  # Here and not in guide_card_lifecycle because only this app opens the event
  # store the desks dispatch into (mcl-om#10), the same reason
  # board_over_mesh_test lives here.
  use ExUnit.Case, async: false

  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewFacts
  alias GuideCardLifecycle.CrewFacts.{CrewFact, CrewStandingReconciler}
  alias GuideCardLifecycle.CrewState

  @key {__MODULE__, :realm_key}
  @at 1_790_000_000_000

  setup_all do
    {:ok, key} = :macula_node_keys.generate(:realm, :pq_pure)
    previous = Application.get_env(:mcl_om, :realm_key)

    Application.put_env(
      :mcl_om,
      :realm_key,
      key |> :macula_node_keys.public_key() |> Base.encode16(case: :lower)
    )

    on_exit(fn -> Application.put_env(:mcl_om, :realm_key, previous) end)
    :persistent_term.put(@key, key)
    :ok
  end

  defp key, do: :persistent_term.get(@key)

  defp node_id(name), do: :crypto.hash(:sha256, "synthetic realm node " <> name)
  defp hex(name), do: Base.encode16(node_id(name), case: :lower)

  defp crew_id(name),
    do: :crypto.hash(:sha256, "synthetic crew id " <> name) |> Base.encode16(case: :lower)

  # A crew named `name`, its operator and one other member. The operator is
  # NOT among the members, which the realm allows: the board enlists it too.
  defp payload(fact, name, over) do
    Map.merge(
      %{
        "fact" => fact,
        "crew_id" => crew_id(name),
        "crew_name" => name,
        "operator_node" => hex(name <> "_op"),
        "operator_name" => name <> "_op",
        "member_nodes" => [hex(name <> "_one")],
        "member_names" => %{hex(name <> "_one") => name <> "_one"},
        "seq" => 1,
        "at" => @at,
        "by" => "citizen:0192f1e0-0000-7000-8000-000000000001"
      },
      over
    )
  end

  # The fact as the realm signs and publishes it, and as a subscriber holds it.
  # The signed bytes cover the payload, which is every field but `fact` and
  # `signature`.
  defp signed(fact, name, over \\ %{}) do
    fields = payload(fact, name, over)

    signature =
      :macula_node_keys.sign(CrewFact.signed_bytes(fact, Map.delete(fields, "fact")), key())

    fields
    |> Map.put("signature", Base.encode16(signature, case: :lower))
    |> Map.new(fn {k, v} -> {{:text, k}, wrapped(v)} end)
  end

  defp wrapped(v) when is_binary(v), do: {:text, v}
  defp wrapped(v) when is_integer(v), do: v
  defp wrapped(v) when is_list(v), do: Enum.map(v, &wrapped/1)
  defp wrapped(v) when is_map(v), do: Map.new(v, fn {k, val} -> {{:text, k}, wrapped(val)} end)

  defp crew, do: CrewAggregate.current()

  test "an admitted crew is enlisted and its operator appointed, and the seq is recorded" do
    name = "radio_room"

    assert {:ok, %{operator: :ok}} =
             CrewFacts.received("admitted", signed("admitted", name, %{"seq" => 4}))

    state = crew()
    assert CrewState.crew_seq(state, crew_id(name)) == 4
    assert CrewState.operator_of(state, name) == hex(name <> "_op")
    assert CrewState.crew_of(state, hex(name <> "_one")) == name
    assert CrewState.crew_of(state, hex(name <> "_op")) == name
  end

  test "the same fact twice acts once" do
    name = "twice_room"
    fact = signed("admitted", name, %{"seq" => 2})

    assert {:ok, _outcome} = CrewFacts.received("admitted", fact)
    assert {:error, :already_observed} = CrewFacts.received("admitted", fact)
    assert CrewState.crew_seq(crew(), crew_id(name)) == 2
  end

  test "a fact signed by another key is refused, and nothing is enlisted" do
    name = "forged_room"
    {:ok, other} = :macula_node_keys.generate(:realm, :pq_pure)
    fields = payload("admitted", name, %{"seq" => 9})

    signature =
      :macula_node_keys.sign(CrewFact.signed_bytes("admitted", Map.delete(fields, "fact")), other)

    wire =
      fields
      |> Map.put("signature", Base.encode16(signature, case: :lower))
      |> Map.new(fn {k, v} -> {{:text, k}, wrapped(v)} end)

    assert {:error, :signature_invalid} = CrewFacts.received("admitted", wire)
    assert CrewState.crew_of(crew(), hex(name <> "_one")) == nil
    assert CrewState.crew_seq(crew(), crew_id(name)) == 0
  end

  test "a fact on another fact's topic is refused" do
    assert {:error, :wrong_topic} =
             CrewFacts.received("revoked", signed("admitted", "topic_room"))
  end

  test "every drop fact drops the crew, whichever reason it carries" do
    for {fact, reason, name} <- [
          {"suspended", "operator_resigned", "suspended_room_a"},
          {"suspended", "operator_ended", "suspended_room_b"},
          {"revoked", "revoked", "revoked_room_a"},
          {"revoked", "operator_revoked", "revoked_room_b"},
          {"left", nil, "left_room"}
        ] do
      extra = if reason, do: %{"reason" => reason}, else: %{}

      assert {:ok, _outcome} =
               CrewFacts.received("admitted", signed("admitted", name, %{"seq" => 1})),
             "admitting #{name}"

      assert {:ok, %{discharged: discharged}} =
               CrewFacts.received(fact, signed(fact, name, Map.put(extra, "seq", 2))),
             "dropping #{name} with #{fact}"

      assert length(discharged) == 2, "#{fact}/#{reason} dropped #{length(discharged)} agents"
      assert CrewState.crew_of(crew(), hex(name <> "_one")) == nil
      assert CrewState.crew_seq(crew(), crew_id(name)) == 2
    end
  end

  test "a revoked crew loses its agents, and its seq moves on" do
    name = "revoked_room"

    assert {:ok, _outcome} =
             CrewFacts.received("admitted", signed("admitted", name, %{"seq" => 1}))

    assert {:ok, %{discharged: discharged}} =
             CrewFacts.received(
               "revoked",
               signed("revoked", name, %{"seq" => 2, "reason" => "revoked"})
             )

    assert Enum.sort(discharged) ==
             Enum.sort([{hex(name <> "_one"), :ok}, {hex(name <> "_op"), :ok}])

    state = crew()
    assert CrewState.crew_of(state, hex(name <> "_one")) == nil
    assert CrewState.operator_of(state, name) == nil
    assert CrewState.crew_seq(state, crew_id(name)) == 2
  end

  test "a replaced operator is appointed, and the previous one dropped" do
    name = "swap_room"

    assert {:ok, _outcome} =
             CrewFacts.received("admitted", signed("admitted", name, %{"seq" => 1}))

    replaced =
      signed("operator_replaced", name, %{
        "seq" => 2,
        "operator_node" => hex(name <> "_two"),
        "operator_name" => name <> "_two",
        "previous_operator_node" => hex(name <> "_op"),
        "member_nodes" => [hex(name <> "_one"), hex(name <> "_two")],
        "member_names" => %{
          hex(name <> "_one") => name <> "_one",
          hex(name <> "_two") => name <> "_two"
        }
      })

    assert {:ok, %{operator: :ok, previous: :ok}} =
             CrewFacts.received("operator_replaced", replaced)

    state = crew()
    assert CrewState.operator_of(state, name) == hex(name <> "_two")
    assert CrewState.crew_of(state, hex(name <> "_op")) == nil
    assert CrewState.crew_of(state, hex(name <> "_two")) == name
  end

  test "a replayed lower seq after a drop re-appoints nobody" do
    name = "replay_room"
    admitted = signed("admitted", name, %{"seq" => 5})
    assert {:ok, _outcome} = CrewFacts.received("admitted", admitted)

    assert {:ok, _outcome} =
             CrewFacts.received(
               "revoked",
               signed("revoked", name, %{"seq" => 6, "reason" => "revoked"})
             )

    assert {:error, :already_observed} = CrewFacts.received("admitted", admitted)
    assert CrewState.operator_of(crew(), name) == nil
  end

  test "the reconcile applies the realm's latest fact, and keeps the crew on its errors" do
    name = "reconciled_room"

    assert {:ok, _outcome} =
             CrewFacts.received("admitted", signed("admitted", name, %{"seq" => 1}))

    id = crew_id(name)

    revoked = signed("revoked", name, %{"seq" => 2, "reason" => "revoked"})
    answered = %{"fact" => "revoked", "payload" => Map.delete(revoked, {:text, "fact"})}

    # every other crew this board knows is answered as one the realm never
    # heard of, which must change nothing
    fetch = fn
      ^id -> {:ok, answered}
      _other -> {:error, "unknown_crew"}
    end

    assert :ok = CrewStandingReconciler.reconcile(fetch)
    state = crew()
    assert CrewState.operator_of(state, name) == nil
    assert CrewState.crew_seq(state, id) == 2

    # the same answer again is the ordinary replay path, not a failure
    assert :ok = CrewStandingReconciler.reconcile(fetch)
    assert CrewState.crew_seq(crew(), id) == 2
  end
end
