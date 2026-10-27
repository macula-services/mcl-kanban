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
  #
  # The `crew` every function takes is a crew KEY (#40 option b): for a crew
  # the realm admitted, its `crew_id`. Nothing here resolves it from a name --
  # the realm's own act names the crew it signed about, never one it guessed.
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

  @doc """
  Drops every agent of `crew` the realm did not keep. A crew fact carries the
  whole roster, so a node this board holds in that crew and the fact does not
  name was dropped by the realm's own record -- a replaced operator, or a
  member who left between two admissions (#40). Keeping it would leave an
  agent on the board acting for a crew that no longer holds it.
  """
  @spec drop_not_kept(String.t(), [String.t()]) :: [{String.t(), act()}]
  def drop_not_kept(crew, kept) do
    CrewAggregate.current()
    |> CrewState.agents_of(crew)
    |> Enum.reject(&(&1 in kept))
    |> Enum.map(&{&1, discharge(&1)})
  end

  defp ours?(state, crew, node, name) do
    CrewState.crew_of(state, node) == crew and
      String.downcase(CrewState.name_of(state, node)) == String.downcase(name)
  end

  defp run({:ok, command}, module), do: module.dispatch(command) |> outcome()
  defp run({:error, reason}, _module), do: {:error, reason}

  # Every refusal the three desks this path drives can name -- the board's own
  # answer to the realm's fact. Anything else a dispatch returns
  # (`too_many_attempts`, a consistency timeout, a store that was not there)
  # is the board failing rather than deciding, and is wrapped as such so the
  # fact stays unrecorded and the next reconcile pass asks again.
  @answers ~w(not_permitted already_enlisted name_taken unknown_agent
              agent_in_another_crew already_appointed supervisor_required
              appointed_by_owner held_in_another_crew)a

  defp outcome({:ok, _version, _events}), do: :ok
  defp outcome({:error, reason}) when is_atom(reason) and reason in @answers, do: {:error, reason}
  defp outcome({:error, reason}), do: {:error, {:not_an_answer, reason}}
end
