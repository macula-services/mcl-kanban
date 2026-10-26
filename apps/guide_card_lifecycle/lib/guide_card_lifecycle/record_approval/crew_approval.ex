defmodule GuideCardLifecycle.RecordApproval.CrewApproval do
  # A crew-approval/v1: the operator's signed yes (or no) on a card (#30).
  #
  # It is a macula_signed_object under the label "crew-approval/v1" that
  # carries its key, so anyone holding the encoded bytes re-verifies it
  # offline: the signature covers the label, the key and the fields exactly
  # as signed, and nothing is re-encoded. The fields, all with text keys:
  #
  #   kind              "range", or a planning gate: "gate:vision",
  #                     "gate:boundary", "gate:design"
  #   card_id           the card the yes is on, so it cannot be replayed onto
  #                     another card of the same repo
  #   operator_node_id  the signer's node id, 64 lowercase hex digits; it must
  #                     derive from the carried key
  #   repo              "org/repo", the card's repo
  #   verdict           1 (yes) or 0 (no), never a boolean
  #   at                when the operator signed, ms since the epoch
  #   nonce             32 lowercase hex digits, fresh for every approval
  #   ref, base, tip    a range: the ref and the two commits (7 to 64 hex)
  #   tag               a range, optionally: the tag it releases
  #   issue             a gate: the plan issue it passes, "org/repo#n"
  #
  # No other field is accepted, so what a verifier reads is all that was
  # signed. read/1 is the whole check that needs no board: shape, signature,
  # and the signer's key against operator_node_id. Whether that node is the
  # operator of the card's home crew, and whether the nonce was seen, the
  # card decides (MaybeRecordApproval).
  @moduledoc false

  alias GuideCardLifecycle.IssueRef

  @label "crew-approval/v1"
  @gates ["gate:vision", "gate:boundary", "gate:design"]
  @common ~w(kind card_id operator_node_id repo verdict at nonce)
  @range_fields @common ++ ~w(ref base tip tag)
  @gate_fields @common ++ ~w(issue)

  @type reason ::
          :approval_malformed | :signature_invalid | :alg_mismatch | :signer_mismatch

  @spec label() :: String.t()
  def label, do: @label

  @doc "The planning gates an approval may pass."
  @spec gates() :: [String.t()]
  def gates, do: @gates

  @doc """
  Signs an approval with an identity key, as the operator's tooling does:
  the fields as plain strings and integers, the result the encoded object.
  """
  @spec sign(map(), :macula_node_keys.node_key()) :: binary()
  def sign(fields, key) do
    signed = Map.new(fields, fn {k, v} -> {{:text, to_string(k)}, wire(v)} end)
    @label |> :macula_signed_object.sign(signed, key) |> :macula_signed_object.encode()
  end

  defp wire(v) when is_binary(v), do: {:text, v}
  defp wire(v) when is_integer(v), do: v

  @doc """
  Reads an encoded approval: its fields as plain strings and integers, with
  the signer's node id, once the signature verifies and the fields are the
  shape of their kind.
  """
  @spec read(binary()) :: {:ok, map()} | {:error, reason()}
  def read(encoded) when is_binary(encoded) do
    with {:ok, object} <- decoded(:macula_signed_object.decode(encoded)),
         {:ok, %{key: key, fields: fields}} <- verified(object),
         {:ok, approval} <- shaped(plain(fields)),
         do: signed_by(approval, :macula_node_keys.node_id(key, profile()))
  end

  def read(_), do: {:error, :approval_malformed}

  defp decoded({:ok, %{key: _} = object}), do: {:ok, object}
  defp decoded(_held_or_malformed), do: {:error, :approval_malformed}

  defp verified(object), do: refusal(:macula_signed_object.verify(@label, object, profile()))

  defp refusal({:error, :malformed}), do: {:error, :approval_malformed}
  defp refusal(result), do: result

  # The fields with their text wrapping and the alg the object adds removed.
  defp plain(fields) do
    for {{:text, k}, v} <- fields, k != "alg", into: %{}, do: {k, unwrap(v)}
  end

  # Text and integers are the only values a field takes; bytes, lists and
  # maps stay wrapped, so no check below can mistake them for either.
  defp unwrap({:text, v}), do: v
  defp unwrap(v) when is_integer(v), do: v
  defp unwrap(v), do: {:not_text_or_integer, v}

  defp shaped(%{"kind" => "range"} = f), do: valid(f, @range_fields, &range/1)
  defp shaped(%{"kind" => gate} = f) when gate in @gates, do: valid(f, @gate_fields, &gate/1)
  defp shaped(_), do: {:error, :approval_malformed}

  # Every key is one the kind allows, and each value is well formed.
  defp valid(fields, allowed, kind_check),
    do:
      well_formed(
        Map.keys(fields) -- allowed == [] and common?(fields) and kind_check.(fields),
        fields
      )

  defp well_formed(true, fields), do: {:ok, fields}
  defp well_formed(false, _fields), do: {:error, :approval_malformed}

  defp common?(f) do
    is_binary(f["card_id"]) and IssueRef.card_id?(f["card_id"]) and
      hex?(f["operator_node_id"], 64, 64) and repo?(f["repo"]) and f["verdict"] in [0, 1] and
      is_integer(f["at"]) and f["at"] > 0 and hex?(f["nonce"], 32, 32)
  end

  defp range(f) do
    text?(f["ref"]) and hex?(f["base"], 7, 64) and hex?(f["tip"], 7, 64) and
      (not Map.has_key?(f, "tag") or text?(f["tag"]))
  end

  defp gate(f), do: is_binary(f["issue"]) and match?({:ok, _}, IssueRef.parse(f["issue"]))

  defp repo?(repo), do: is_binary(repo) and match?({:ok, _}, IssueRef.repo(repo))

  defp text?(t), do: is_binary(t) and String.trim(t) != "" and byte_size(t) <= 255

  defp hex?(h, min, max) when is_binary(h),
    do: byte_size(h) in min..max and h =~ ~r/\A[0-9a-f]+\z/

  defp hex?(_h, _min, _max), do: false

  # The node id must derive from the key that signed.
  defp signed_by(%{"operator_node_id" => claimed} = approval, derived) do
    case Base.encode16(derived, case: :lower) do
      ^claimed -> {:ok, approval}
      _other -> {:error, :signer_mismatch}
    end
  end

  defp profile do
    {:ok, profile} = :macula_crypto_profile.configured()
    profile
  end
end
