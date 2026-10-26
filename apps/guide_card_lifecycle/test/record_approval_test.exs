defmodule GuideCardLifecycle.RecordApprovalTest do
  # record_approval (#30): the operator of a card's home crew signs a
  # crew-approval/v1, and any agent brings it to the card. Keys are generated
  # per run (identity keys of the configured profile); node ids derive from
  # them, so nothing here names a real node. The live read of the home
  # crew's operator is MaybeRecordApproval.dispatch/1's, end to end in
  # MclKanban.BoardOverMeshTest; here the command carries it as dispatch
  # would put it.
  use ExUnit.Case, async: true

  import GuideCardLifecycle.TestCrew

  alias GuideCardLifecycle.CardState
  alias GuideCardLifecycle.IssueRef
  alias GuideCardLifecycle.QueueCard.{MaybeQueueCard, QueueCardV1}
  alias GuideCardLifecycle.RecordApproval.{CrewApproval, MaybeRecordApproval, RecordApprovalV1}

  @ref "example-org/widget#7"
  @other_ref "example-org/widget#8"
  @repo "example-org/widget"

  setup_all do
    {:ok, profile} = :macula_crypto_profile.configured()

    keys =
      for who <- [:home_operator, :night_operator, :agent], into: %{}, do: {who, key(profile)}

    {:ok, keys: keys}
  end

  defp key(profile) do
    {:ok, key} = :macula_node_keys.generate(:identity, profile)
    key
  end

  defp node_hex(key) do
    {:ok, id} = :macula_node_keys.node_id(key)
    Base.encode16(id, case: :lower)
  end

  defp nonce, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

  defp range(key, overrides \\ %{}) do
    Map.merge(
      %{
        kind: "range",
        card_id: IssueRef.card_id(@ref),
        operator_node_id: node_hex(key),
        repo: @repo,
        ref: "main",
        base: "5d2a04fc9453637693e8c8aeb4a434fcb4947af1",
        tip: "1d44f85d3eb7bdd81a3c0bc30b1d810b93eb4910",
        tag: "v0.6.0",
        verdict: 1,
        at: System.system_time(:millisecond),
        nonce: nonce()
      },
      overrides
    )
  end

  defp gate(key, kind) do
    %{
      kind: kind,
      card_id: IssueRef.card_id(@ref),
      operator_node_id: node_hex(key),
      repo: @repo,
      issue: @ref,
      verdict: 1,
      at: System.system_time(:millisecond),
      nonce: nonce()
    }
  end

  defp signed(fields, key), do: fields |> CrewApproval.sign(key) |> Base.encode64()

  defp wire(v) when is_binary(v), do: {:text, v}
  defp wire(v) when is_integer(v), do: v

  defp card(ref \\ @ref) do
    {:ok, queue} =
      QueueCardV1.new(%{issue_ref: ref, title: "Draw it", kind: "slice", by: actor("cyd")})

    {:ok, events} =
      MaybeQueueCard.handle(CardState.new(IssueRef.card_id(ref)), %{queue | home_crew: "home"})

    Enum.reduce(events, CardState.new(IssueRef.card_id(ref)), &CardState.apply_event(&2, &1))
  end

  # The command as dispatch/1 sends it: the home crew's operator read live.
  defp command(approval, keys, ref \\ @ref) do
    with {:ok, cmd} <-
           RecordApprovalV1.new(%{
             card_id: IssueRef.card_id(ref),
             approval: approval,
             by: actor("cyd")
           }),
         do: {:ok, %{cmd | home_operator: node_hex(keys.home_operator)}}
  end

  defp record(card, approval, keys, ref \\ @ref) do
    with {:ok, cmd} <- command(approval, keys, ref), do: MaybeRecordApproval.handle(card, cmd)
  end

  defp recorded(card, approval, keys) do
    {:ok, events} = record(card, approval, keys)
    Enum.reduce(events, card, &CardState.apply_event(&2, &1))
  end

  test "the home crew operator's signed yes on a range is recorded, verbatim", %{keys: keys} do
    approval = range(keys.home_operator) |> signed(keys.home_operator)

    assert {:ok, [event]} = record(card(), approval, keys)
    assert event.event_type == "approval_recorded_v1"
    assert event.kind == "range"
    assert event.verdict == 1
    assert event.tag == "v0.6.0"
    assert event.operator_node_id == node_hex(keys.home_operator)
    assert event.approval == approval
    assert {:ok, _} = approval |> Base.decode64!() |> CrewApproval.read()
  end

  test "a no is recorded as a no: verdict 0", %{keys: keys} do
    approval = range(keys.home_operator, %{verdict: 0}) |> signed(keys.home_operator)
    assert {:ok, [%{verdict: 0}]} = record(card(), approval, keys)
  end

  test "each planning gate is recorded on the card it names", %{keys: keys} do
    for kind <- CrewApproval.gates() do
      approval = gate(keys.home_operator, kind) |> signed(keys.home_operator)
      assert {:ok, [%{kind: ^kind, issue: @ref}]} = record(card(), approval, keys)
    end
  end

  test "a valid signature by another crew's operator is refused", %{keys: keys} do
    approval = range(keys.night_operator) |> signed(keys.night_operator)
    assert {:error, :not_home_operator} = record(card(), approval, keys)
  end

  test "an agent's key is refused", %{keys: keys} do
    approval = range(keys.agent) |> signed(keys.agent)
    assert {:error, :not_home_operator} = record(card(), approval, keys)
  end

  test "a card whose home crew has no operator refuses every approval", %{keys: keys} do
    approval = range(keys.home_operator) |> signed(keys.home_operator)
    {:ok, cmd} = command(approval, keys)

    assert {:error, :not_home_operator} =
             MaybeRecordApproval.handle(card(), %{cmd | home_operator: nil})
  end

  test "a replayed nonce is refused", %{keys: keys} do
    approval = range(keys.home_operator) |> signed(keys.home_operator)
    card = recorded(card(), approval, keys)

    assert {:error, :replayed_nonce} = record(card, approval, keys)

    # The same nonce under a fresh signature over other fields is a replay too.
    again =
      range(keys.home_operator, %{nonce: hd(MapSet.to_list(card.approval_nonces)), verdict: 0})

    assert {:error, :replayed_nonce} = record(card, signed(again, keys.home_operator), keys)
  end

  test "a yes for one card, brought to another with the same nonce, is wrong_card", %{keys: keys} do
    approval = range(keys.home_operator) |> signed(keys.home_operator)
    _first = recorded(card(), approval, keys)

    assert {:error, :wrong_card} = record(card(@other_ref), approval, keys, @other_ref)
  end

  test "a yes naming another repo is refused", %{keys: keys} do
    approval =
      range(keys.home_operator, %{repo: "example-org/gadget"}) |> signed(keys.home_operator)

    assert {:error, :wrong_repo} = record(card(), approval, keys)
  end

  test "a tampered field breaks the signature", %{keys: keys} do
    approval = range(keys.home_operator) |> CrewApproval.sign(keys.home_operator)
    {:ok, object} = :macula_signed_object.decode(approval)
    {:ok, fields} = :macula_record_cbor.decode_strict(object.tbs)

    tampered_tbs =
      :macula_record_cbor.encode(
        Map.put(fields, {:text, "tip"}, {:text, String.duplicate("a", 40)})
      )

    tampered = :macula_signed_object.encode(%{object | tbs: tampered_tbs}) |> Base.encode64()

    assert {:error, :signature_invalid} = record(card(), tampered, keys)
  end

  test "a key that is not the operator_node_id it names is refused", %{keys: keys} do
    claimed = range(keys.home_operator)
    assert {:error, :signer_mismatch} = record(card(), signed(claimed, keys.agent), keys)
  end

  test "an approval that is not the shape of its kind is malformed", %{keys: keys} do
    op = keys.home_operator

    for fields <- [
          range(op, %{verdict: 2}),
          range(op, %{kind: "gate:launch"}),
          range(op, %{issue: @ref}),
          range(op, %{nonce: "not-hex"}),
          range(op, %{tip: "xyz"}),
          # A range binds two exact commits: an abbreviation can name two.
          range(op, %{tip: "1d44f85"}),
          range(op, %{base: "5d2a04fc9453637693e8c8aeb4a434fcb4947af"}),
          range(op, %{tip: String.duplicate("a", 64)}),
          range(op, %{base: "5D2A04FC9453637693E8C8AEB4A434FCB4947AF1"}),
          Map.delete(range(op), :base),
          Map.delete(gate(op, "gate:design"), :issue),
          Map.put(gate(op, "gate:design"), :tip, "1d44f85")
        ] do
      assert {:error, :approval_malformed} = record(card(), signed(fields, op), keys),
             inspect(fields)
    end

    # A field under an integer key is signed too, so it is no field to drop.
    integer_keyed =
      range(op)
      |> Map.new(fn {k, v} -> {{:text, to_string(k)}, wire(v)} end)
      |> Map.put(1, {:text, "x"})

    smuggled =
      CrewApproval.label()
      |> :macula_signed_object.sign(integer_keyed, op)
      |> :macula_signed_object.encode()
      |> Base.encode64()

    assert {:error, :approval_malformed} = record(card(), smuggled, keys)

    assert {:error, :approval_malformed} = record(card(), "not base64!", keys)
    assert {:error, :approval_malformed} = record(card(), Base.encode64("not cbor"), keys)
  end

  test "only an enlisted agent brings an approval to the board", %{keys: keys} do
    approval = range(keys.home_operator) |> signed(keys.home_operator)
    {:ok, cmd} = command(approval, keys)

    assert {:error, :not_permitted} =
             MaybeRecordApproval.handle(card(), %{cmd | by: GuideCardLifecycle.Actor.owner()})
  end
end
