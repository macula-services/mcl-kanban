defmodule MclKanban.RecordApproval.RecordApprovalResponder do
  # mcl-kanban/record_approval: card_id, approval (the encoded
  # crew-approval/v1 as standard base64 text). Any enlisted agent brings it;
  # the operator's signature decides (#30). Replies card_id, kind, verdict and
  # nonce once the read model holds it, or the refusal's reason.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.RecordApproval.{MaybeRecordApproval, RecordApprovalV1}
  alias MclKanban.Wire

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, cmd} <-
             RecordApprovalV1.new(%{
               card_id: Wire.arg(payload, :card_id),
               approval: Wire.arg(payload, :approval),
               by: by
             }),
           {:ok, version, _events} <- MaybeRecordApproval.dispatch(cmd),
           do:
             Wire.once_read(cmd.card_id, version, %{
               card_id: cmd.card_id,
               kind: cmd.kind,
               verdict: cmd.verdict,
               nonce: cmd.nonce
             })

    {:reply, Wire.reply(reply), state}
  end
end
