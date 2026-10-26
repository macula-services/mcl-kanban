defmodule GuideCardLifecycle.CrewState do
  # The crew as the crew aggregate holds it: enlisted agents by node id (hex)
  # with the crew each belongs to (#28), the operator of each crew, the node
  # ids of the supervisor and the prioritiser, and its goal (#18).
  @moduledoc false

  alias GuideCardLifecycle.CrewName

  defstruct agents: %{}, operators: %{}, supervisor: nil, prioritiser: nil, goal: nil

  @type t :: %__MODULE__{
          agents: %{String.t() => %{name: String.t(), crew: String.t()}},
          operators: %{String.t() => String.t()},
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
  def name_of(%__MODULE__{agents: agents}, node_id), do: with(%{} = agent <- Map.get(agents, node_id), do: agent.name)

  @doc "The crew an enlisted agent belongs to, or nil for a node the crew does not know."
  @spec crew_of(t(), String.t() | nil) :: String.t() | nil
  def crew_of(%__MODULE__{agents: agents}, node_id), do: with(%{} = agent <- Map.get(agents, node_id), do: agent.crew)

  @doc "The node id of a crew's operator, or nil while it has none."
  @spec operator_of(t(), String.t()) :: String.t() | nil
  def operator_of(%__MODULE__{operators: operators}, crew), do: Map.get(operators, crew)

  @doc """
  Every crew the roster knows: the ones agents are enlisted into, plus any
  that holds an operator. Sorted, so a listing is stable.
  """
  @spec crew_names(t()) :: [String.t()]
  def crew_names(%__MODULE__{agents: agents, operators: operators}) do
    (Enum.map(agents, fn {_node_id, a} -> a.crew end) ++ Map.keys(operators))
    |> Enum.uniq()
    |> Enum.sort()
  end

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

  def apply_event(state, _other), do: state

  # An event from before #28 carries no crew: those agents belong to the home crew.
  defp crew_in(%{crew: crew}) when is_binary(crew), do: crew
  defp crew_in(_event), do: CrewName.home()

  defp unless_is(id, id), do: nil
  defp unless_is(kept, _id), do: kept
end
