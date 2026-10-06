defmodule MclKanban.DischargeAgent.DischargeAgentResponder do
  # mcl-kanban/discharge_agent: name. The supervisor discharges an agent (never the supervisor). Replies the agent.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.DischargeAgent.{MaybeDischargeAgent, DischargeAgentV1}
  alias MclKanban.Wire

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, cmd} <-
             DischargeAgentV1.new(Map.put(%{name: Wire.arg(payload, :name)}, :by, by)),
           {:ok, _version, _events} <- MaybeDischargeAgent.dispatch(cmd),
           do: {:ok, %{agent: %{name: cmd.name}}}

    {:reply, Wire.reply(reply), state}
  end
end
