defmodule GuideCardLifecycle.CrewFacts.CrewFactTest do
  # The shape half of the reader (mcl-kanban#40): what a crew fact may say,
  # as it arrives on the wire. Nothing here needs a key, and nothing here
  # verifies anything.
  use ExUnit.Case, async: true

  alias GuideCardLifecycle.CrewFacts.CrewFact

  @crew_id String.duplicate("a", 64)
  @operator String.duplicate("b", 64)
  @previous String.duplicate("d", 64)
  @member String.duplicate("c", 64)
  @signature String.duplicate("e", 96)

  # Wire form: keys and text values wrapped as {:text, _}, integers bare,
  # which is what mcl_om hands a subscriber.
  defp wire(fields), do: Map.new(fields, fn {k, v} -> {{:text, to_string(k)}, wrapped(v)} end)

  defp wrapped(v) when is_binary(v), do: {:text, v}
  defp wrapped(v) when is_integer(v), do: v
  defp wrapped(v) when is_list(v), do: Enum.map(v, &wrapped/1)
  defp wrapped(v) when is_map(v), do: Map.new(v, fn {k, val} -> {{:text, k}, wrapped(val)} end)
  defp wrapped(v), do: v

  defp fields(over \\ %{}) do
    Map.merge(
      %{
        "fact" => "admitted",
        "crew_id" => @crew_id,
        "crew_name" => "night",
        "operator_node" => @operator,
        "operator_name" => "eve",
        "member_nodes" => [@member],
        "member_names" => %{@member => "cyd"},
        "seq" => 1,
        "at" => 1_790_000_000_000,
        "by" => "mri:org:io.macula/rgfaber",
        "signature" => @signature
      },
      over
    )
  end

  defp read(over), do: CrewFact.read(wire(fields(over)))

  test "reads an admitted crew, with its fields as plain strings and integers" do
    assert {:ok, %{fact: "admitted", payload: payload, signature: @signature}} = read(%{})

    assert payload == %{
             "crew_id" => @crew_id,
             "crew_name" => "night",
             "operator_node" => @operator,
             "operator_name" => "eve",
             "member_nodes" => [@member],
             "member_names" => %{@member => "cyd"},
             "seq" => 1,
             "at" => 1_790_000_000_000,
             "by" => "mri:org:io.macula/rgfaber"
           }
  end

  test "reads each fact with the field only it carries" do
    for {fact, extra, reason} <- [
          {"operator_replaced", %{"previous_operator_node" => @previous}, nil},
          {"suspended", %{}, "operator_resigned"},
          {"suspended", %{}, "operator_ended"},
          {"revoked", %{}, "revoked"},
          {"revoked", %{}, "operator_revoked"},
          {"left", %{}, nil}
        ] do
      over =
        case reason do
          nil -> Map.merge(%{"fact" => fact}, extra)
          reason -> Map.merge(%{"fact" => fact, "reason" => reason}, extra)
        end

      assert {:ok, %{fact: read_fact}} = read(over), "read refused #{fact} #{inspect(reason)}"
      assert read_fact == fact
    end
  end

  test "a fact it does not know is refused as such, never acted on" do
    assert {:error, :unknown_crew_fact} = read(%{"fact" => "promoted"})
  end

  test "a missing field and an extra field are both refused" do
    assert {:error, :crew_fact_malformed} = CrewFact.read(wire(Map.delete(fields(), "by")))
    assert {:error, :crew_fact_malformed} = read(%{"nickname" => "eve"})
  end

  test "a drop reason is refused where the fact does not take one, and outside its own set" do
    assert {:error, :crew_fact_malformed} = read(%{"reason" => "revoked"})

    assert {:error, :crew_fact_malformed} =
             read(%{"fact" => "suspended", "reason" => "operator_revoked"})

    assert {:error, :crew_fact_malformed} =
             read(%{"fact" => "revoked", "reason" => "operator_resigned"})

    assert {:error, :crew_fact_malformed} = read(%{"fact" => "left", "reason" => "revoked"})
    assert {:error, :crew_fact_malformed} = read(%{"fact" => "operator_replaced"})
  end

  test "a boolean is refused: the wire never carries one" do
    assert {:error, :crew_fact_malformed} = read(%{"seq" => true})
    assert {:error, :crew_fact_malformed} = read(%{"member_nodes" => [true]})
  end

  test "ids are 64 lowercase hex, and a crew name is one the board can hold" do
    for bad <- [
          %{"crew_id" => String.upcase(@crew_id)},
          %{"crew_id" => String.duplicate("a", 63)},
          %{"operator_node" => "zz" <> String.duplicate("0", 62)},
          %{"member_nodes" => [@member, @member]},
          %{"member_nodes" => [@member, "nope"]},
          %{"crew_name" => "1night"},
          %{"crew_name" => String.duplicate("n", 41)},
          %{"by" => ""},
          %{"seq" => 0},
          %{"at" => -1}
        ] do
      assert {:error, :crew_fact_malformed} = read(bad), "accepted #{inspect(bad)}"
    end
  end

  test "the names are the board's own: one per member, and none of them reserved" do
    for bad <- [
          %{"operator_name" => "owner"},
          %{"operator_name" => "realm"},
          %{"operator_name" => "1eve"},
          %{"operator_name" => ""},
          %{"member_names" => %{}},
          %{"member_names" => %{@member => "cyd", @previous => "ada"}},
          %{"member_names" => %{@member => "owner"}},
          %{"member_names" => %{@member => "bad name"}},
          %{"member_names" => %{@member => 12}},
          %{"operator_node" => @member, "member_names" => %{@member => "cyd"}}
        ] do
      assert {:error, :crew_fact_malformed} = read(bad), "accepted #{inspect(bad)}"
    end

    # the operator may also be a member, and then both fields name it the same
    assert {:ok, %{payload: %{"member_names" => %{@member => "eve"}, "operator_name" => "eve"}}} =
             read(%{"operator_node" => @member, "member_names" => %{@member => "eve"}})
  end

  test "a signature must be there, and lowercase hex" do
    assert {:error, :crew_fact_malformed} = CrewFact.read(wire(Map.delete(fields(), "signature")))
    assert {:error, :crew_fact_malformed} = read(%{"signature" => String.upcase(@signature)})
    assert {:error, :crew_fact_malformed} = read(%{"signature" => "not-hex"})
    assert {:error, :crew_fact_malformed} = read(%{"signature" => 12})
  end

  test "a map that is not a map is refused, not raised on" do
    assert {:error, :crew_fact_malformed} = CrewFact.read("nope")

    assert {:error, :crew_fact_malformed} =
             CrewFact.read(%{{:bytes, "fact"} => {:text, "admitted"}})
  end

  test "the signed bytes are the same every time, and change with any field" do
    {:ok, %{fact: fact, payload: payload}} = read(%{})

    bytes = CrewFact.signed_bytes(fact, payload)
    assert bytes == CrewFact.signed_bytes(fact, payload)
    assert is_binary(bytes) and byte_size(bytes) > 0

    for {k, v} <- [{"crew_id", String.duplicate("f", 64)}, {"seq", 2}, {"crew_name", "day"}] do
      changed = Map.put(payload, k, v)
      refute CrewFact.signed_bytes(fact, changed) == bytes, "#{k} did not change the bytes"
    end

    refute CrewFact.signed_bytes("revoked", payload) == bytes
  end

  test "a fact's topic is the realm's own crew namespace" do
    realm = String.duplicate("1", 64)

    for fact <- CrewFact.facts() do
      assert CrewFact.topic(realm, fact) == :macula_topic.realm_fact(realm, "crew", fact, 1)
    end
  end
end
