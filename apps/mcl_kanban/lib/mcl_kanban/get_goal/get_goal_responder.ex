defmodule MclKanban.GetGoal.GetGoalResponder do
  # mcl-kanban/get_goal: no arguments. The crew's goal (#18): goal, packages,
  # by and at (unix ms); no goal key before one is adopted. Enlisted agents.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias MclKanban.Wire
  alias QueryBoards.GetGoal.GetGoal

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply = with {:ok, _by} <- Actor.of_caller(payload), do: {:ok, %{goal: GetGoal.get_goal()}}
    {:reply, Wire.reply(reply), state}
  end
end
