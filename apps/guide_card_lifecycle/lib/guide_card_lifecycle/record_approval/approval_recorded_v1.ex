defmodule GuideCardLifecycle.RecordApproval.ApprovalRecordedV1 do
  # Event: approval_recorded_v1. Carries the approval as read and, under
  # `approval`, the encoded object as base64 text exactly as it arrived, so
  # anyone re-verifies it offline. `by` is whoever brought it to the board;
  # operator_node_id is who signed it.
  @moduledoc false

  alias GuideCardLifecycle.CardEvent

  def event_type, do: "approval_recorded_v1"

  def new(cmd, status) do
    fields =
      Map.take(cmd, [
        :kind,
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
        :approval
      ])

    CardEvent.new(event_type(), cmd.card_id, cmd.by, status, fields)
  end
end
