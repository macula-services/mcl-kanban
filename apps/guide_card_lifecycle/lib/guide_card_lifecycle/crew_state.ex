defmodule GuideCardLifecycle.CrewState do
  # The crew as the crew aggregate holds it: enlisted agents by node id (hex),
  # the node ids of the supervisor and the prioritiser, and its goal (#18).
  @moduledoc false

  defstruct agents: %{}, supervisor: nil, prioritiser: nil, goal: nil

  @type t :: %__MODULE__{
          agents: %{String.t() => String.t()},
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
    Enum.find_value(agents, fn {node_id, n} -> String.downcase(n) == wanted && node_id end)
  end

  @spec name_of(t(), String.t() | nil) :: String.t() | nil
  def name_of(%__MODULE__{agents: agents}, node_id), do: Map.get(agents, node_id)

  @spec apply_event(t(), map()) :: t()
  def apply_event(state, %{data: data, event_type: type}),
    do: apply_event(state, Map.put(data, :event_type, type))

  def apply_event(state, %{event_type: "agent_enlisted_v1", node_id: id, name: name}),
    do: %{state | agents: Map.put(state.agents, id, name)}

  def apply_event(state, %{event_type: "agent_discharged_v1", node_id: id}) do
    %{state | agents: Map.delete(state.agents, id), prioritiser: unless_is(state.prioritiser, id)}
  end

  def apply_event(state, %{event_type: "supervisor_appointed_v1", node_id: id}),
    do: %{state | supervisor: id}

  def apply_event(state, %{event_type: "prioritiser_appointed_v1", node_id: id}),
    do: %{state | prioritiser: id}

  def apply_event(state, %{event_type: "goal_adopted_v1"} = e),
    do: %{state | goal: %{goal: e.goal, packages: e.packages, by: e.by, at: e.at}}

  def apply_event(state, _other), do: state

  defp unless_is(id, id), do: nil
  defp unless_is(kept, _id), do: kept
end
