defmodule GuideCardLifecycle.CrewFacts.RealmSignatureTest do
  # The pinned realm key and the signature check (mcl-kanban#40, R4). The
  # board acts on a fact only when THIS says the realm signed it, so these are
  # the tests that hold the refusal, not the happy path alone.
  #
  # Not async: configured_key/0 reads :mcl_om's application env, which is one
  # global.
  use ExUnit.Case, async: false

  alias GuideCardLifecycle.CrewFacts.{CrewFact, RealmSignature}

  @crew_id String.duplicate("a", 64)
  @operator String.duplicate("b", 64)
  @member String.duplicate("c", 64)

  defp wire(fields), do: Map.new(fields, fn {k, v} -> {{:text, to_string(k)}, wrapped(v)} end)

  defp wrapped(v) when is_binary(v), do: {:text, v}
  defp wrapped(v) when is_integer(v), do: v
  defp wrapped(v) when is_list(v), do: Enum.map(v, &wrapped/1)
  defp wrapped(v) when is_map(v), do: Map.new(v, fn {k, val} -> {{:text, k}, wrapped(val)} end)

  # A fact as the realm publishes one, with the stub signature a shape reader
  # takes: the real one is made below, over the bytes this fact reads to.
  defp fact(over) do
    Map.merge(
      %{
        "fact" => "admitted",
        "crew_id" => @crew_id,
        "crew_name" => "night",
        "operator_node" => @operator,
        "operator_name" => "ada",
        "member_nodes" => [@member],
        "member_names" => %{@member => "cyd"},
        "seq" => 1,
        "at" => 1_790_000_000_000,
        "by" => "mri:org:io.macula/rgfaber",
        "signature" => String.duplicate("0", 96)
      },
      over
    )
  end

  defp realm_key(profile) do
    {:ok, key} = :macula_node_keys.generate(:realm, profile)
    key
  end

  defp hex_key(key) do
    key |> :macula_node_keys.public_key() |> Base.encode16(case: :lower)
  end

  # A fact signed as the realm signs one: over the canonical encoding of the
  # fields as read, then carried as lowercase hex.
  defp signed(profile, over \\ %{}) do
    key = realm_key(profile)
    {:ok, %{fact: fact, payload: payload}} = CrewFact.read(wire(fact(over)))
    signature = :macula_node_keys.sign(CrewFact.signed_bytes(fact, payload), key)

    {wire(fact(Map.put(over, "signature", Base.encode16(signature, case: :lower)))), hex_key(key),
     profile}
  end

  test "the key comes from the deploy pin, and an unset one is refused by name" do
    original = Application.get_env(:mcl_om, :realm_key)
    on_exit(fn -> Application.put_env(:mcl_om, :realm_key, original) end)

    hex = hex_key(realm_key(:pq_pure))

    Application.put_env(:mcl_om, :realm_key, hex)
    assert {:ok, %{profile: :pq_pure, key: key}} = RealmSignature.configured_key()
    assert Base.encode16(key, case: :lower) == hex

    Application.put_env(:mcl_om, :realm_key, "")
    assert {:error, :realm_key_unset} = RealmSignature.configured_key()

    Application.put_env(:mcl_om, :realm_key, nil)
    assert {:error, :realm_key_unset} = RealmSignature.configured_key()
  end

  test "a key that is not even-length hex is refused, naming the variable's problem" do
    for bad <- ["abc", "zz", "a", String.duplicate("a", 7)] do
      assert {:error, :realm_key_not_hex} = RealmSignature.realm_key(bad), "accepted #{bad}"
    end
  end

  test "the profile is the key's own shape, not this board's configured one" do
    assert {:ok, %{profile: :pq_pure}} = RealmSignature.realm_key(hex_key(realm_key(:pq_pure)))

    assert {:ok, %{profile: :pq_hybrid}} =
             RealmSignature.realm_key(hex_key(realm_key(:pq_hybrid)))
  end

  test "a hex key that is not a realm key of either profile is refused" do
    assert {:error, :realm_key_not_a_profile_key} =
             RealmSignature.realm_key(Base.encode16(:crypto.strong_rand_bytes(40), case: :lower))
  end

  test "the realm's signature over a fact verifies, and nothing else does" do
    {wire_fact, key_hex, _profile} = signed(:pq_pure)
    {:ok, key} = RealmSignature.realm_key(key_hex)

    {:ok, %{fact: fact, payload: payload, signature: signature}} = CrewFact.read(wire_fact)
    assert :ok = RealmSignature.verify(CrewFact.signed_bytes(fact, payload), signature, key)

    # a field changed after signing is refused
    tampered = Map.put(payload, "seq", 2)

    assert {:error, :signature_invalid} =
             RealmSignature.verify(CrewFact.signed_bytes(fact, tampered), signature, key)

    # a signature by another key is refused
    other = realm_key(:pq_pure)

    assert {:error, :signature_invalid} =
             RealmSignature.verify(CrewFact.signed_bytes(fact, payload), signature, %{
               key: :macula_node_keys.public_key(other),
               profile: :pq_pure
             })

    # a signature that is not lowercase hex, or the wrong length, is refused
    assert {:error, :signature_invalid} =
             RealmSignature.verify(
               CrewFact.signed_bytes(fact, payload),
               String.upcase(signature),
               key
             )

    assert {:error, :signature_invalid} =
             RealmSignature.verify(
               CrewFact.signed_bytes(fact, payload),
               String.slice(signature, 0, 20),
               key
             )
  end

  test "a hybrid realm verifies the same way: the profile follows the key" do
    {wire_fact, key_hex, :pq_hybrid} = signed(:pq_hybrid)
    {:ok, key} = RealmSignature.realm_key(key_hex)
    {:ok, %{fact: fact, payload: payload, signature: signature}} = CrewFact.read(wire_fact)

    assert :ok = RealmSignature.verify(CrewFact.signed_bytes(fact, payload), signature, key)

    assert {:error, :signature_invalid} =
             RealmSignature.verify(
               CrewFact.signed_bytes(fact, Map.put(payload, "seq", 9)),
               signature,
               key
             )
  end

  test "a key that is half a profile is not used to verify anything" do
    {wire_fact, _key_hex, _profile} = signed(:pq_pure)
    {:ok, %{fact: fact, payload: payload, signature: signature}} = CrewFact.read(wire_fact)
    bytes = CrewFact.signed_bytes(fact, payload)

    for key <- [
          nil,
          %{},
          %{key: "short", profile: :pq_pure},
          %{key: :binary.copy(<<0>>, 2592), profile: :not_a_profile}
        ] do
      assert {:error, :signature_invalid} = RealmSignature.verify(bytes, signature, key)
    end
  end
end
