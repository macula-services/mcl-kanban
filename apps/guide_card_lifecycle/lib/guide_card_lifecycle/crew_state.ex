defmodule GuideCardLifecycle.CrewState do
  # The crew as the crew aggregate holds it: enlisted agents by node id (hex)
  # with the crew KEY each belongs to (#28, #40), the operator of each crew key,
  # the node ids of the supervisor and the prioritiser, its goal (#18), and the
  # crews the realm has admitted, by crew id, at the last fact seq the board
  # accepted (#40).
  #
  # A crew is held by its KEY: a crew the realm admitted by its `crew_id`, a
  # crew the owner made by its name. The two shapes cannot collide, so one
  # field carries both, and nothing here has to ask which kind it holds.
  @moduledoc false

  alias GuideCardLifecycle.CrewName

  defstruct agents: %{},
            operators: %{},
            crews: %{},
            supervisor: nil,
            prioritiser: nil,
            goal: nil

  @type t :: %__MODULE__{
          agents: %{String.t() => %{name: String.t(), crew: String.t()}},
          operators: %{String.t() => String.t()},
          crews: %{
            String.t() => %{name: String.t(), seq: non_neg_integer(), discharged?: boolean()}
          },
          supervisor: String.t() | nil,
          prioritiser: String.t() | nil,
          goal: map() | nil
        }

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "The node id of an enlisted agent, by name (case-insensitive)."
  @spec node_id_of(t(), String.t()) :: String.t() | nil
  def node_id_of(%__MODULE__{agents: agents}, name) do
    wanted = String.downcase(name)
    Enum.find_value(agents, fn {node_id, a} -> String.downcase(a.name) == wanted && node_id end)
  end

  @spec name_of(t(), String.t() | nil) :: String.t() | nil
  def name_of(%__MODULE__{agents: agents}, node_id),
    do: with(%{} = agent <- Map.get(agents, node_id), do: agent.name)

  @doc "The crew key an enlisted agent belongs to, or nil for a node the crew does not know."
  @spec crew_of(t(), String.t() | nil) :: String.t() | nil
  def crew_of(%__MODULE__{agents: agents}, node_id),
    do: with(%{} = agent <- Map.get(agents, node_id), do: agent.crew)

  @doc "The node id of a crew's operator, or nil while it has none."
  @spec operator_of(t(), String.t()) :: String.t() | nil
  def operator_of(%__MODULE__{operators: operators}, crew), do: Map.get(operators, crew)

  @doc """
  Every crew key the roster knows: the ones agents are enlisted into, plus any
  that holds an operator. Sorted, so a listing is stable.
  """
  @spec crew_keys(t()) :: [String.t()]
  def crew_keys(%__MODULE__{agents: agents, operators: operators}) do
    (Enum.map(agents, fn {_node_id, a} -> a.crew end) ++ Map.keys(operators))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  The key a crew named in a command resolves to (#40 option b): enlisting,
  appointing and reserving name a crew, and every one of them has to land on
  the key the roster holds that crew under.

  Exactly one admitted crew with that name binds to its id; none means a crew
  the owner made, whose name is its own key. It is refused rather than guessed
  when the name is not one crew's: two admitted crews sharing it, or an
  admitted crew sharing it with a crew the board's own roster already answers
  to -- guessing would dispatch acts against a crew nobody named, and the
  caller has the id to say which one. An id is already a key and resolves to
  itself, since no crew is named one.

  The home crew is the board's own whatever the realm invites: it is where an
  agent enlisted without a crew lands, so its name always answers itself. A
  realm crew invited under that name is reached by its id, never silently by
  the default a dialog starts with.
  """
  @spec crew_key_for(t(), String.t()) :: {:ok, String.t()} | {:error, :crew_name_ambiguous}
  def crew_key_for(%__MODULE__{} = state, name) do
    if name == CrewName.home(), do: {:ok, name}, else: resolved(state, name)
  end

  defp resolved(%__MODULE__{crews: crews} = state, name) do
    case for({id, %{name: ^name, discharged?: false}} <- crews, do: id) do
      [] -> {:ok, name}
      [id] -> if board_crew?(state, name), do: {:error, :crew_name_ambiguous}, else: {:ok, id}
      _several -> {:error, :crew_name_ambiguous}
    end
  end

  # Whether a crew the owner made already answers to this name: its agents are
  # held under the bare name, since a name is its own key.
  defp board_crew?(%__MODULE__{agents: agents}, name),
    do: Enum.any?(agents, fn {_node_id, agent} -> agent.crew == name end)

  @doc """
  The name a person reads a crew key under (#40): the name the realm admitted
  it as, or the key itself for a crew the owner made, whose name it is.
  """
  @spec display_name(t(), String.t()) :: String.t()
  def display_name(%__MODULE__{crews: crews}, key) do
    case Map.get(crews, key) do
      %{name: name} -> name
      nil -> key
    end
  end

  @doc """
  The seq of the last crew fact this board accepted for a crew, or 0 for one
  it has never heard from (#40).
  """
  @spec crew_seq(t(), String.t()) :: non_neg_integer()
  def crew_seq(%__MODULE__{crews: crews}, crew_id) do
    crews |> Map.get(crew_id, %{seq: 0}) |> Map.fetch!(:seq)
  end

  @doc """
  The name this board holds a crew it has not discharged under, or nil for one
  it has never heard from and for one the realm no longer knows (#40).
  """
  @spec crew_name(t(), String.t()) :: String.t() | nil
  def crew_name(%__MODULE__{crews: crews}, crew_id) do
    case Map.get(crews, crew_id) do
      %{name: name, discharged?: false} -> name
      _unknown_or_discharged -> nil
    end
  end

  @doc """
  The crews the realm has told this board about and the board has not
  discharged, each with the id it must be asked about at: the reconcile's work
  list (#40). A discharged crew is not asked about again, which is what stops
  the board from dropping the crew it no longer knows every few passes
  forever.
  """
  @spec live_crews(t()) :: [{String.t(), String.t()}]
  def live_crews(%__MODULE__{crews: crews}) do
    for {crew_id, %{name: name, discharged?: false}} <- crews, do: {crew_id, name}
  end

  @doc "The node ids enlisted in one crew, as the roster holds them (#40)."
  @spec agents_of(t(), String.t()) :: [String.t()]
  def agents_of(%__MODULE__{agents: agents}, crew),
    do: for({node_id, %{crew: ^crew}} <- agents, do: node_id)

  @spec apply_event(t(), map()) :: t()
  def apply_event(state, %{data: data, event_type: type}),
    do: apply_event(state, Map.put(data, :event_type, type))

  def apply_event(state, %{event_type: "agent_enlisted_v1", node_id: id, name: name} = e),
    do: %{state | agents: Map.put(state.agents, id, %{name: name, crew: crew_in(e)})}

  def apply_event(state, %{event_type: "agent_discharged_v1", node_id: id}) do
    %{
      state
      | agents: Map.delete(state.agents, id),
        prioritiser: unless_is(state.prioritiser, id),
        operators:
          state.operators
          |> Enum.reject(fn {_crew, operator} -> operator == id end)
          |> Map.new()
    }
  end

  def apply_event(state, %{event_type: "supervisor_appointed_v1", node_id: id}),
    do: %{state | supervisor: id}

  def apply_event(state, %{event_type: "prioritiser_appointed_v1", node_id: id}),
    do: %{state | prioritiser: id}

  # One operator per crew: appointing another replaces the one sitting.
  def apply_event(state, %{event_type: "operator_appointed_v1", crew: crew, node_id: id}),
    do: %{state | operators: Map.put(state.operators, crew, id)}

  def apply_event(state, %{event_type: "goal_adopted_v1"} = e),
    do: %{state | goal: %{goal: e.goal, packages: e.packages, by: e.by, at: e.at}}

  # The board accepted the realm's fact at this seq: the highest one wins, and
  # the handler refuses anything that is not higher, so this is never lowered.
  # A fact from a crew the board had discharged makes it live again: the realm
  # knows it, so the board does too.
  def apply_event(state, %{event_type: "crew_fact_observed_v1"} = e) do
    %{
      state
      | crews:
          Map.put(state.crews, e.crew_id, %{name: e.crew_name, seq: e.seq, discharged?: false})
    }
  end

  # The board discharged a crew the realm stopped knowing (#40): its agents go
  # with it, its operator seat empties, and its seq is kept so a replay of an
  # old fact still cannot re-enlist anyone.
  def apply_event(state, %{event_type: "crew_discharged_v1"} = e) do
    crews =
      Map.update(
        state.crews,
        e.crew,
        %{name: nil, seq: 0, discharged?: true},
        &%{
          &1
          | discharged?: true
        }
      )

    %{state | crews: crews, operators: Map.delete(state.operators, e.crew)}
  end

  def apply_event(state, _other), do: state

  # An event from before #28 carries no crew: those agents belong to the home crew.
  defp crew_in(%{crew: crew}) when is_binary(crew), do: crew
  defp crew_in(_event), do: CrewName.home()

  defp unless_is(id, id), do: nil
  defp unless_is(kept, _id), do: kept
end
