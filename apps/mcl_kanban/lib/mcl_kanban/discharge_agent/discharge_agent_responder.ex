defmodule MclKanban.DischargeAgent.DischargeAgentResponder do
  # mcl-kanban/discharge_agent: name. A crew's own operator — or the owner —
  # discharges an agent of that crew (#28), never the supervisor. Replies the
  # agent.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.DischargeAgent.{MaybeDischargeAgent, DischargeAgentV1}
  alias MclKanban.Wire
  alias QueryBoards.GetCrew.GetCrew

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, cmd} <-
             DischargeAgentV1.new(Map.put(%{name: Wire.arg(payload, :name)}, :by, by)),
           {:ok, _version, [event]} <- MaybeDischargeAgent.dispatch(cmd),
           :ok <- GetCrew.await_discharged(discharged_node(event)),
           do: {:ok, %{agent: %{name: cmd.name}}}

    {:reply, Wire.reply(reply), state}
  end

  # The aggregate resolves the name case-insensitively and the event carries
  # the node it found; the projection deletes by that node, so the await keys on
  # it too — a discharge typed in another case than the enlist's still waits for
  # its own row to go.
  defp discharged_node(%{data: %{node_id: node_id}}), do: node_id
  defp discharged_node(%{node_id: node_id}), do: node_id
end
