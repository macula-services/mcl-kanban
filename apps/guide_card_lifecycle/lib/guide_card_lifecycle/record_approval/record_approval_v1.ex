defmodule GuideCardLifecycle.RecordApproval.RecordApprovalV1 do
  # Command: record an operator's signed approval on a card (#30). It takes
  # the encoded crew-approval/v1 as standard base64 text and keeps that text
  # verbatim, so the event holds exactly the bytes the operator signed. new/1
  # checks what needs no board (CrewApproval.read/1); the card checks the
  # rest. home_operator is never read from the caller: dispatch/1 in
  # MaybeRecordApproval writes it from the live crew.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, IssueRef}
  alias GuideCardLifecycle.RecordApproval.CrewApproval

  @enforce_keys [:card_id, :approval, :by]
  defstruct [
    :card_id,
    :approval,
    :by,
    :kind,
    :approval_card_id,
    :operator_node_id,
    :repo,
    :verdict,
    :signed_at,
    :nonce,
    :ref,
    :base,
    :tip,
    :tag,
    :issue,
    :home_operator
  ]

  @max_approval_bytes 16_384

  @impl true
  def command_type, do: :record_approval

  @impl true
  def new(%{card_id: id, approval: approval, by: %Actor{} = by}) do
    with {:ok, id} <- IssueRef.valid_card_id(id),
         {:ok, encoded} <- encoded(approval),
         {:ok, fields} <- CrewApproval.read(encoded),
         do: {:ok, command(id, approval, by, fields)}
  end

  def new(_), do: {:error, :missing_required_fields}

  defp encoded(text) when is_binary(text) and byte_size(text) <= @max_approval_bytes,
    do: decoded(Base.decode64(text))

  defp encoded(_), do: {:error, :approval_malformed}

  defp decoded({:ok, bytes}), do: {:ok, bytes}
  defp decoded(:error), do: {:error, :approval_malformed}

  defp command(id, approval, by, f) do
    %__MODULE__{
      card_id: id,
      approval: approval,
      by: by,
      kind: f["kind"],
      approval_card_id: f["card_id"],
      operator_node_id: f["operator_node_id"],
      repo: f["repo"],
      verdict: f["verdict"],
      signed_at: f["at"],
      nonce: f["nonce"],
      ref: f["ref"],
      base: f["base"],
      tip: f["tip"],
      tag: f["tag"],
      issue: f["issue"]
    }
  end

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
