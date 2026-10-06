defmodule MclKanban.ResumeCard.ResumeCardResponder do
  # mcl-kanban/resume_card: card_id. The prioritiser or the owner resumes a deferred card: queued
  # again, unranked (#17). Replies the card.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.ResumeCard.{MaybeResumeCard, ResumeCardV1}
  alias MclKanban.{CardProcedure, Wire}

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    args = %{card_id: Wire.arg(payload, :card_id)}
    {:reply, CardProcedure.call(payload, ResumeCardV1, MaybeResumeCard, args), state}
  end
end
