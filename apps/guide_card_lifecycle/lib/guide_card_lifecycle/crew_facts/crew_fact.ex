defmodule GuideCardLifecycle.CrewFacts.CrewFact do
  # A crew fact the realm signs: the board learns a crew was admitted, its
  # operator replaced, or the crew suspended, revoked or gone (#40, contract
  # from macula-realm#107's threat model R3/R4/R7).
  #
  # It arrives on the wire as a CBOR map with text keys, which mcl_om hands a
  # subscriber still in wire form: keys and text values wrapped as {:text, _},
  # integers bare. Every fact carries crew_id, crew_name, operator_node,
  # operator_name, member_nodes, member_names, seq, at and by, plus one of
  # previous_operator_node (operator_replaced) or reason (suspended, revoked,
  # and left when the realm says it); the signature is a lowercase hex ML-DSA
  # signature by the realm's signing key, over the canonical encoding of
  #
  #   %{tag: "macula.realm.crew_fact", v: 1, fact: fact, payload: fields}
  #
  # with `fields` every field but the signature, and text wrapped as {:text, _}
  # as it arrives (a bare binary would encode as a byte string, a different
  # signature). Nothing is ever re-encoded from the wire bytes: signed_bytes/2
  # rebuilds that map canonically, so the same fact always gives the same bytes.
  #
  # A crew fact carries the NAMES, not only the node ids: the board keys its
  # agents by name, and a name read from anywhere but the signed fact would be
  # a second trust path beside the realm's. So member_names holds one name per
  # member node and operator_name the operator's, all of them names the board
  # can hold (AgentName, which reserves "owner" and "realm").
  #
  # The FACT ITSELF is not in the payload: the topic names it (and the
  # reconcile's answer says it beside the payload), so a payload carrying one
  # is carrying a field nobody reads, which read/2 refuses. That is also why
  # the topic is the fact's proof of itself: the signed bytes are rebuilt with
  # the name the caller was told, so a fact published on another fact's topic
  # verifies as nothing at all.
  #
  # read/2 is the shape half of the reader and nothing else: what a verifier
  # acts on is exactly the fields it read here, so a field this refuses can
  # never be part of what was signed. The signature is checked next, by
  # RealmSignature, and only then does anything act on the fact.
  @moduledoc false

  alias GuideCardLifecycle.AgentName
  alias GuideCardLifecycle.CrewName

  @tag "macula.realm.crew_fact"
  @version 1

  @facts ~w(admitted operator_replaced suspended revoked left)
  @common ~w(crew_id crew_name operator_node operator_name member_nodes member_names seq at by)
  @allowed %{
    "admitted" => @common,
    "operator_replaced" => @common ++ ~w(previous_operator_node),
    "suspended" => @common ++ ~w(reason),
    "revoked" => @common ++ ~w(reason),
    "left" => @common
  }

  # The reasons each drop fact may carry (R3, and the operator's departure
  # paths in the threat model's section 5). `left` is the realm's own
  # crew_left_v1, which records `reason: "left"`; it may arrive with it or
  # without, and a `left` that says anything else is refused.
  @reasons %{
    "suspended" => ~w(operator_resigned operator_ended),
    "revoked" => ~w(revoked operator_revoked),
    "left" => ~w(left)
  }

  # The one fact whose reason is optional: a drop off the board must never be
  # lost for the sake of a field that changes nothing about it.
  @optional %{"left" => ~w(reason)}

  @type fact() :: String.t()
  @type reason() :: :crew_fact_malformed | :unknown_crew_fact

  @doc "Every fact this board acts on."
  @spec facts() :: [fact()]
  def facts, do: @facts

  @doc "The topic a fact is published on: <realm>/_realm/_realm/crew/<fact>_v1."
  @spec topic(binary(), fact()) :: binary()
  def topic(realm, fact) when fact in @facts,
    do: :macula_topic.realm_fact(realm, "crew", fact, @version)

  @doc """
  Reads `fact` as it came off its topic: the wire is its fields with its
  signature, and the fact itself is named by that topic -- or by the
  reconcile's answer beside it. Shape only; nothing is verified.
  """
  @spec read(fact(), map()) ::
          {:ok, %{fact: fact(), payload: map(), signature: binary()}} | {:error, reason()}
  def read(fact, wire) when is_binary(fact) and is_map(wire) do
    with :ok <- known(fact),
         {:ok, plain} <- plain(wire),
         {:ok, signature} <- signature_of(plain),
         {:ok, payload} <- payload_of(fact, plain),
         do: {:ok, %{fact: fact, payload: payload, signature: signature}}
  end

  def read(_fact, _wire), do: {:error, :crew_fact_malformed}

  defp known(fact) when fact in @facts, do: :ok
  defp known(_fact), do: {:error, :unknown_crew_fact}

  @doc """
  The bytes the realm's signature covers, rebuilt from the fields. The
  encoding is canonical (map keys sorted by their encoded bytes), so the same
  fact always gives the same bytes.
  """
  @spec signed_bytes(fact(), map()) :: binary()
  def signed_bytes(fact, payload) do
    :macula_record_cbor.encode(%{
      {:text, "tag"} => {:text, @tag},
      {:text, "v"} => @version,
      {:text, "fact"} => {:text, fact},
      {:text, "payload"} => keyed(payload)
    })
  end

  # The wire form unwrapped. A key or a value of another shape is refused
  # rather than guessed at: a boolean is not a field this reader takes, which
  # is also how "no booleans on the wire" is held here.
  defp plain(raw) do
    Enum.reduce_while(raw, {:ok, %{}}, fn {k, v}, {:ok, acc} ->
      case {key(k), value(v)} do
        {nil, _} -> {:halt, {:error, :crew_fact_malformed}}
        {_, :error} -> {:halt, {:error, :crew_fact_malformed}}
        {key, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
      end
    end)
  end

  defp key({:text, k}) when is_binary(k), do: k
  defp key(k) when is_atom(k), do: Atom.to_string(k)
  defp key(_k), do: nil

  defp value({:text, v}) when is_binary(v), do: v
  defp value(v) when is_integer(v), do: v
  defp value(v) when is_list(v), do: list(v)
  defp value(v) when is_map(v), do: nested(v)
  defp value(_v), do: :error

  defp nested(map) do
    case plain(map) do
      {:ok, plain} -> plain
      {:error, _reason} -> :error
    end
  end

  defp list(vs) do
    Enum.reduce_while(vs, [], fn v, acc ->
      case value(v) do
        :error -> {:halt, :error}
        value -> {:cont, [value | acc]}
      end
    end)
    |> case do
      :error -> :error
      reversed -> Enum.reverse(reversed)
    end
  end

  # The fields the fact allows and no others: a fact carrying a field nobody
  # reads is refused rather than signed off, since a verifier cannot tell an
  # extra field from a changed one. A "fact" in the payload is one of those:
  # the topic names the fact, so nothing puts it in the signed payload.
  defp payload_of(fact, plain) do
    required = Map.fetch!(@allowed, fact)
    optional = Map.get(@optional, fact, [])
    fields = Map.delete(plain, "signature")

    well_formed(keys?(fields, required, optional) and fields_of(fact, fields), fields)
  end

  defp keys?(fields, required, optional) do
    keys = Map.keys(fields)

    required -- keys == [] and keys -- (required ++ optional) == []
  end

  defp well_formed(true, fields), do: {:ok, fields}
  defp well_formed(false, _fields), do: {:error, :crew_fact_malformed}

  defp fields_of(fact, fields), do: common?(fields) and extras_of(fact, fields)

  # The fields every fact carries, in three reads so no one of them carries the
  # whole shape: who the crew is, who staffs it, and what stamp the fact bears.
  defp common?(f), do: identified?(f) and staffed?(f) and stamped?(f)

  defp identified?(f), do: hex?(f["crew_id"]) and crew_name?(f["crew_name"])

  # `names?` runs only once `members?` has said member_nodes is a list.
  defp staffed?(f) do
    hex?(f["operator_node"]) and agent_name?(f["operator_name"]) and
      members?(f["member_nodes"]) and names?(f["member_names"], f["member_nodes"]) and
      operator_named?(f)
  end

  defp stamped?(f) do
    is_integer(f["seq"]) and f["seq"] > 0 and is_integer(f["at"]) and f["at"] > 0 and
      text?(f["by"])
  end

  defp extras_of("operator_replaced", f), do: hex?(f["previous_operator_node"])

  defp extras_of(fact, f) when is_map_key(@reasons, fact) do
    case Map.fetch(f, "reason") do
      {:ok, reason} -> reason in Map.fetch!(@reasons, fact)
      :error -> "reason" in Map.get(@optional, fact, [])
    end
  end

  defp extras_of(_fact, _fields), do: true

  defp crew_name?(name), do: match?({:ok, _}, CrewName.name(name))

  defp agent_name?(name), do: match?({:ok, _}, AgentName.name(name))

  # A crew's members are node ids with no repeats: a repeated id would be two
  # members in one node id, which nothing on the board can hold.
  defp members?(nodes) when is_list(nodes),
    do: Enum.all?(nodes, &hex?/1) and length(Enum.uniq(nodes)) == length(nodes)

  defp members?(_nodes), do: false

  # One name per member node and no other: a member without a name could not be
  # enlisted, and a name for a node the fact does not list is a name the realm
  # and the board would disagree about.
  defp names?(names, nodes) when is_map(names) and is_list(nodes) do
    Enum.sort(Map.keys(names)) == Enum.sort(nodes) and
      Enum.all?(Map.values(names), &agent_name?/1)
  end

  defp names?(_names, _nodes), do: false

  # When the operator is one of the members, both fields name the same agent.
  defp operator_named?(%{
         "member_names" => names,
         "operator_node" => node,
         "operator_name" => name
       })
       when is_map(names),
       do: Map.get(names, node, name) == name

  defp operator_named?(_fields), do: false

  defp hex?(h) when is_binary(h), do: h =~ ~r/\A[0-9a-f]{64}\z/
  defp hex?(_h), do: false

  defp text?(t), do: is_binary(t) and String.trim(t) != "" and byte_size(t) <= 255

  defp signature_of(%{"signature" => signature}) when is_binary(signature) do
    if signature =~ ~r/\A[0-9a-f]+\z/, do: {:ok, signature}, else: {:error, :crew_fact_malformed}
  end

  defp signature_of(_plain), do: {:error, :crew_fact_malformed}

  # The payload as the encoding writes it: keys as text, strings as text,
  # integers as integers, the member list element by element.
  defp keyed(payload), do: Map.new(payload, fn {k, v} -> {{:text, k}, wire(v)} end)

  defp wire(v) when is_binary(v), do: {:text, v}
  defp wire(v) when is_integer(v), do: v
  defp wire(v) when is_list(v), do: Enum.map(v, &wire/1)
  defp wire(v) when is_map(v), do: keyed(v)
end
