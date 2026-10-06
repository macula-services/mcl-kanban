defmodule MclKanban.EnlistAgent.EnlistAgentResponder do
  # mcl-kanban/enlist_agent: name, node_id (64 hex). The supervisor enlists an agent; that node id then acts on the board as that name. Replies the agent.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.EnlistAgent.{MaybeEnlistAgent, EnlistAgentV1}
  alias MclKanban.Wire

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, cmd} <-
             EnlistAgentV1.new(
               Map.put(
                 %{name: Wire.arg(payload, :name), node_id: Wire.arg(payload, :node_id)},
                 :by,
                 by
               )
             ),
           {:ok, _version, _events} <- MaybeEnlistAgent.dispatch(cmd),
           do: {:ok, %{agent: %{name: cmd.name, node_id: cmd.node_id}}}

    {:reply, Wire.reply(reply), state}
  end
end
