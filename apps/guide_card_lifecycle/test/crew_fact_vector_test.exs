defmodule GuideCardLifecycle.CrewFacts.CrewFactVectorTest do
  # The realm's own vector (macula-realm#107), checked byte for byte: the board
  # reads the contract the realm signed, and acts on nothing else. Copied from
  # macula-io/macula-realm branch jupiter/107-build @ 9d33c9a,
  # apps/macula_realm/test/macula_realm/mesh/crew_fact_vector.json.
  use ExUnit.Case, async: true

  alias GuideCardLifecycle.CrewFacts.{CrewFact, RealmSignature}

  @vector Path.join(__DIR__, "fixtures/crew_fact_vector.json") |> File.read!() |> JSON.decode!()

  # The same fact as a subscriber receives it: text keys and text values
  # wrapped, integers bare.
  defp wire do
    @vector["payload"]
    |> Map.put("fact", @vector["fact"])
    |> Map.put("signature", @vector["signature_hex"])
    |> Map.new(fn {k, v} -> {{:text, k}, wrapped(v)} end)
  end

  defp wrapped(v) when is_binary(v), do: {:text, v}
  defp wrapped(v) when is_integer(v), do: v
  defp wrapped(v) when is_list(v), do: Enum.map(v, &wrapped/1)
  defp wrapped(v) when is_map(v), do: Map.new(v, fn {k, val} -> {{:text, k}, wrapped(val)} end)

  test "the realm's payload rebuilds to the realm's own message bytes" do
    message = CrewFact.signed_bytes(@vector["fact"], @vector["payload"])

    assert Base.encode16(message, case: :lower) == @vector["message_hex"]
  end

  test "the reader takes the fact the realm wrote, names and all" do
    assert {:ok, %{fact: "admitted", payload: payload, signature: signature}} =
             CrewFact.read(wire())

    assert payload == @vector["payload"]
    assert signature == @vector["signature_hex"]
    assert payload["operator_name"] == "acme-op"

    assert payload["member_names"] == %{
             "0202020202020202020202020202020202020202020202020202020202020202" => "builder",
             "0303030303030303030303030303030303030303030303030303030303030303" => "reviewer_2"
           }
  end

  test "the realm's signature over those bytes verifies against its pinned key" do
    assert @vector["profile"] == "pq_pure"
    assert {:ok, key} = RealmSignature.realm_key(@vector["public_key_hex"])
    assert key.profile == :pq_pure

    assert {:ok, %{fact: fact, payload: payload, signature: signature}} = CrewFact.read(wire())
    assert :ok = RealmSignature.verify(CrewFact.signed_bytes(fact, payload), signature, key)
  end

  test "a field changed after the realm signed it is refused" do
    {:ok, key} = RealmSignature.realm_key(@vector["public_key_hex"])
    assert {:ok, %{fact: fact, payload: payload, signature: signature}} = CrewFact.read(wire())

    names = payload["member_names"]
    [one, two] = payload["member_nodes"]

    for changed <- [
          Map.put(payload, "operator_name", "intruder"),
          Map.put(payload, "member_names", %{one => "intruder", two => names[two]}),
          Map.put(payload, "seq", payload["seq"] + 1)
        ] do
      assert {:error, :signature_invalid} =
               RealmSignature.verify(CrewFact.signed_bytes(fact, changed), signature, key)
    end
  end

  test "the topic is the realm fact topic the contract names" do
    assert CrewFact.topic("io.macula", @vector["fact"]) == @vector["topic_on_io_macula"]
  end
end
