defmodule GuideCardLifecycle.CrewFacts.SubscriptionsTest do
  # What the board asks mcl_om to subscribe to (mcl-kanban#40). macula 18
  # refuses a subscription that names no source (macula#147), and mcl_om 1.6
  # refuses the boot of a service whose subscriptions/0 is not in its shape, so
  # a service that gets this wrong fails loudly rather than running deaf. This
  # holds the reading: a subscription added later without `sources` fails here,
  # in the suite, before a box has to boot to find out.
  #
  # Not async: configured_key/0 reads :mcl_om's application env, which is one
  # global.
  use ExUnit.Case, async: false

  alias GuideCardLifecycle.CrewFacts
  alias GuideCardLifecycle.CrewFacts.{CrewFact, CrewFactSubscriber}

  defp put_key(value) do
    original = Application.get_env(:mcl_om, :realm_key)
    Application.put_env(:mcl_om, :realm_key, value)
    original
  end

  defp hex_key(key), do: key |> :macula_node_keys.public_key() |> Base.encode16(case: :lower)

  test "no realm key, no subscriptions: nothing heard could have been verified" do
    original = put_key("")
    on_exit(fn -> Application.put_env(:mcl_om, :realm_key, original) end)

    assert CrewFacts.subscriptions() == []
  end

  test "one subscription per fact, in mcl_om 1.6's shape, each naming its source" do
    {:ok, key} = :macula_node_keys.generate(:realm, :pq_pure)
    original = put_key(hex_key(key))
    on_exit(fn -> Application.put_env(:mcl_om, :realm_key, original) end)

    subscriptions = CrewFacts.subscriptions()

    assert length(subscriptions) == length(CrewFact.facts())

    assert Enum.all?(subscriptions, &match?(%{sources: :members}, &1)),
           "a subscription named no source; macula 18 refuses that one"

    for %{topic: topic, module: CrewFactSubscriber, args: fact, sources: :members} <-
          subscriptions do
      assert topic == CrewFacts.topic(fact)
      assert fact in CrewFact.facts()
    end
  end
end
