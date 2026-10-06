defmodule MclKanban.AdoptGoal.AdoptGoalResponder do
  # mcl-kanban/adopt_goal: goal (one sentence), packages (one or two
  # work-package issue refs). The supervisor adopts the crew's one goal;
  # claim_next_card serves its packages first (#18). Replies the goal.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AdoptGoal.{AdoptGoalV1, MaybeAdoptGoal}
  alias MclKanban.Wire
  alias QueryBoards.GetGoal.GetGoal

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, cmd} <-
             AdoptGoalV1.new(%{
               goal: Wire.arg(payload, :goal),
               packages: Wire.texts(Wire.arg(payload, :packages)),
               by: by
             }),
           {:ok, _version, [event]} <- MaybeAdoptGoal.dispatch(cmd),
           :ok <- GetGoal.await_adopted(adopted_at(event)),
           do: {:ok, %{goal: %{goal: cmd.goal, packages: cmd.packages}}}

    {:reply, Wire.reply(reply), state}
  end

  defp adopted_at(%{data: %{at: at}}), do: at
  defp adopted_at(%{at: at}), do: at
end
