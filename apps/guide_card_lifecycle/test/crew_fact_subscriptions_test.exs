defmodule GuideCardLifecycle.CrewFacts.SubscriptionsTest do
  # What the board asks mcl_om to subscribe to (mcl-kanban#40). macula 18
  # refuses a subscription that names no source (macula#147), and mcl_om 1.6
  # refuses the boot of a service whose subscriptions/0 is not in its shape, so
  # a service that gets this wrong fails loudly rather than running deaf. This
  # holds the reading: a subscription added later without `sources` fails here,
  # in the suite, before a box has to boot to find out.
  #
  # The source is the realm's PINNED PUBLISHING NODE, not `members`. `members`
  # reads a member endorsement the realm's own node does not have, on either
  # realm, so it would refuse every crew fact (macula-io/macula-realm#168).
  #
  # Not async: configured_key/0 and configured_publisher/0 read :mcl_om's
  # application env, which is one global.
  use ExUnit.Case, async: false

  alias GuideCardLifecycle.CrewFacts
  alias GuideCardLifecycle.CrewFacts.{CrewFact, CrewFactSubscriber}

  # A node id as the mesh writes one: 32 bytes, 64 hex characters.
  @publisher_hex "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
  @publisher_bytes Base.decode16!(@publisher_hex, case: :lower)

  defp put(key, value) do
    original = Application.get_env(:mcl_om, key)
    Application.put_env(:mcl_om, key, value)
    on_exit(fn -> Application.put_env(:mcl_om, key, original) end)
  end

  defp hex_key(key), do: key |> :macula_node_keys.public_key() |> Base.encode16(case: :lower)

  defp with_realm_key do
    {:ok, key} = :macula_node_keys.generate(:realm, :pq_pure)
    put(:realm_key, hex_key(key))
  end

  test "no realm key, no subscriptions: nothing heard could have been verified" do
    put(:realm_key, "")
    put(:crew_fact_publisher, @publisher_hex)

    assert CrewFacts.subscriptions() == []
  end

  test "a realm key but no publishing node: the board declares nothing rather than guess" do
    with_realm_key()
    put(:crew_fact_publisher, "")

    assert CrewFacts.subscriptions() == []
  end

  test "a publishing node that is not 32 bytes of hex is refused, not silently dropped" do
    with_realm_key()

    put(:crew_fact_publisher, String.slice(@publisher_hex, 2..-1//1))
    assert CrewFacts.subscriptions() == []

    put(:crew_fact_publisher, String.duplicate("z", 64))
    assert CrewFacts.subscriptions() == []
  end

  test "one subscription per fact, in mcl_om 1.6's shape, each naming the realm's node" do
    with_realm_key()
    put(:crew_fact_publisher, @publisher_hex)

    subscriptions = CrewFacts.subscriptions()

    assert length(subscriptions) == length(CrewFact.facts())

    assert Enum.all?(subscriptions, &match?(%{sources: {:nodes, [@publisher_bytes]}}, &1)),
           "a subscription named a source other than the realm's publishing node"

    for %{topic: topic, module: CrewFactSubscriber, args: fact, sources: {:nodes, [_node]}} <-
          subscriptions do
      assert topic == CrewFacts.topic(fact)
      assert fact in CrewFact.facts()
    end
  end

  test "a 0x-prefixed node id is the same node" do
    with_realm_key()
    put(:crew_fact_publisher, "0x" <> @publisher_hex)

    assert [%{sources: {:nodes, [@publisher_bytes]}} | _] = CrewFacts.subscriptions()
  end
end
