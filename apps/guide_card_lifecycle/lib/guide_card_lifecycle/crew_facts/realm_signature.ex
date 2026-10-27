defmodule GuideCardLifecycle.CrewFacts.RealmSignature do
  # The pinned realm key, and the one signature check the board trusts a crew
  # fact by (mcl-kanban#40, threat model R4).
  #
  # The pin is the key the deploy already carries: `:mcl_om, :realm_key`, from
  # MCL_REALM_KEY, the realm's public signing key in hex (config/runtime.exs).
  # It is the same key mcl_om hands macula as `realm_trust`, so the board has
  # one pin and not two, and an unset one stops the consumer at boot rather
  # than at the first fact.
  #
  # The profile is the KEY's, not this board's: a realm may run the EU form or
  # the US form, and the board verifies whatever realm it was pinned to. The
  # key says which by its own shape (a pure ML-DSA key, or that key followed by
  # an RSA half), so nothing here reads the board's own crypto profile.
  @moduledoc false

  @type key :: %{key: binary(), profile: :pq_pure | :pq_hybrid}
  @type reason ::
          :realm_key_unset
          | :realm_key_not_hex
          | :realm_key_not_a_profile_key
          | :signature_invalid

  @doc """
  The pinned realm key, decoded, with the profile its shape names. Takes the
  hex a deploy carries, so a boot check and its test load the key the same way.

  A key with no value at all is unset, not malformed: mcl_om writes an empty
  string for a variable the deploy did not set, so "" and nil both name the
  missing pin rather than blame its characters.
  """
  @spec realm_key(binary() | nil) :: {:ok, key()} | {:error, reason()}
  def realm_key(""), do: {:error, :realm_key_unset}

  def realm_key(hex) when is_binary(hex) do
    with {:ok, bytes} <- decode(hex), do: profiled(bytes)
  end

  def realm_key(_unset), do: {:error, :realm_key_unset}

  @doc """
  The key this board is deployed with, from mcl_om's own pin. An unset one is
  an error here, not a silent "everything fails to verify".
  """
  @spec configured_key() :: {:ok, key()} | {:error, reason()}
  def configured_key, do: realm_key(Application.get_env(:mcl_om, :realm_key))

  @doc """
  Whether the realm signed these bytes. Act on nothing else: a fact whose
  signature does not verify is never a fact, however it arrived.
  """
  @spec verify(binary(), binary(), key()) :: :ok | {:error, :signature_invalid}
  def verify(bytes, signature_hex, %{key: key, profile: profile}) when is_binary(signature_hex) do
    with {:ok, signature} <- decode_signature(signature_hex),
         true <- :macula_node_keys.verify(bytes, signature, key, profile) do
      :ok
    else
      _refused -> {:error, :signature_invalid}
    end
  end

  def verify(_bytes, _signature, _key), do: {:error, :signature_invalid}

  # mcl_om's own rule for this pin (mcl_om_identity: hex_shaped/1 and
  # realm_key_decoded/2): even length and hex characters, checked before
  # decoding so a stray character names the variable rather than raising.
  defp decode(hex) do
    if byte_size(hex) > 0 and rem(byte_size(hex), 2) == 0 and hex =~ ~r/\A[0-9a-fA-F]+\z/ do
      Base.decode16(hex, case: :mixed)
    else
      {:error, :realm_key_not_hex}
    end
  end

  defp profiled(bytes) do
    cond do
      :macula_node_keys.carried_key_well_formed(bytes, :pq_pure) ->
        {:ok, %{key: bytes, profile: :pq_pure}}

      :macula_node_keys.carried_key_well_formed(bytes, :pq_hybrid) ->
        {:ok, %{key: bytes, profile: :pq_hybrid}}

      true ->
        {:error, :realm_key_not_a_profile_key}
    end
  end

  defp decode_signature(hex) do
    if rem(byte_size(hex), 2) == 0 and hex =~ ~r/\A[0-9a-f]+\z/ do
      Base.decode16(hex, case: :lower)
    else
      :error
    end
  end
end
