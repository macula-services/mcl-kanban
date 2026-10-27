defmodule GuideCardLifecycle.CrewFacts.RealmActs do
  # The three things a crew fact asks the board to do, each acted AS THE
  # REALM (#40, threat model R4): enlist a member, appoint an operator,
  # discharge an agent, and dropping a whole crew. Every one goes through the
  # desk that already owns the rule, so a crew fact can never do more than an
  # operator could; the realm actor is only ever built after the realm's
  # signature verified.
  #
  # Each act reads the live crew first: dispatching one act changes the roster,
  # and the next act must see that change.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AppointOperator.{AppointOperatorV1, MaybeAppointOperator}
  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewState
  alias GuideCardLifecycle.DischargeAgent.{DischargeAgentV1, MaybeDischargeAgent}
  alias GuideCardLifecycle.EnlistAgent.{EnlistAgentV1, MaybeEnlistAgent}

  @type refusal :: {:error, term()}
  @type act :: :ok | refusal()

  @doc """
  Enlists `{node, name}` into `crew` when the board does not hold that node
  yet. A node already held in that crew under that name is left alone; one
  held anywhere else is refused rather than moved, since a node belongs to one
  crew on this board.
  """
  @spec enlist(String.t(), {String.t(), String.t()}) :: act()
  def enlist(crew, {node, name}) do
    state = CrewAggregate.current()

    cond do
      CrewState.name_of(state, node) == nil ->
        EnlistAgentV1.new(%{name: name, node_id: node, crew: crew, by: Actor.realm()})
        |> run(MaybeEnlistAgent)

      ours?(state, crew, node, name) ->
        :ok

      true ->
        {:error, :held_in_another_crew}
    end
  end

  @doc "Appoints `name` as the operator of `crew`, unless it already is."
  @spec appoint(String.t(), String.t()) :: act()
  def appoint(crew, name) do
    state = CrewAggregate.current()
    node = CrewState.node_id_of(state, name)

    cond do
      node == nil ->
        {:error, :unknown_agent}

      CrewState.operator_of(state, crew) == node ->
        :ok

      true ->
        AppointOperatorV1.new(%{crew: crew, name: name, by: Actor.realm()})
        |> run(MaybeAppointOperator)
    end
  end

  @doc """
  Discharges the agent holding `node`. The supervisor and an owner-appointed
  prioritiser are refused by the desk, and that refusal is reported: the crew
  is still dropped, because its agents act only on its own boards (#29).
  """
  @spec discharge(String.t()) :: act()
  def discharge(node) do
    name = CrewState.name_of(CrewAggregate.current(), node)

    if name == nil do
      {:error, :unknown_agent}
    else
      DischargeAgentV1.new(%{name: name, by: Actor.realm()}) |> run(MaybeDischargeAgent)
    end
  end

  @doc "Drops a whole crew: every agent enlisted in it is discharged, as the realm."
  @spec discharge_crew(String.t()) :: [{String.t(), act()}]
  def discharge_crew(crew) do
    CrewAggregate.current()
    |> CrewState.agents_of(crew)
    |> Enum.map(&{&1, discharge(&1)})
  end

  defp ours?(state, crew, node, name) do
    CrewState.crew_of(state, node) == crew and
      String.downcase(CrewState.name_of(state, node)) == String.downcase(name)
  end

  defp run({:ok, command}, module), do: module.dispatch(command) |> outcome()
  defp run({:error, reason}, _module), do: {:error, reason}

  defp outcome({:ok, _version, _events}), do: :ok
  defp outcome({:error, reason}), do: {:error, reason}
end
