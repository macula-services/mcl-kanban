defmodule GuideCardLifecycle.CrewAggregate do
  # The crew: ONE roster, one stream. Enlisting, discharging and the two
  # appointments are serialised here, so the invariant "exactly one supervisor
  # once founded" holds without a lock.
  @moduledoc false

  @behaviour :evoq_aggregate

  alias GuideCardLifecycle.AdoptGoal.MaybeAdoptGoal
  alias GuideCardLifecycle.AppointPrioritiser.MaybeAppointPrioritiser
  alias GuideCardLifecycle.AppointSupervisor.MaybeAppointSupervisor
  alias GuideCardLifecycle.CrewState
  alias GuideCardLifecycle.DischargeAgent.MaybeDischargeAgent
  alias GuideCardLifecycle.EnlistAgent.MaybeEnlistAgent
  alias GuideCardLifecycle.LiveState

  # A user stream id: the prefix, a dash and 32 hex digits. The suffix is the
  # first half of sha256("mcl-kanban crew"), fixed forever.
  @stream_id "crew-" <>
               (:crypto.hash(:sha256, "mcl-kanban crew")
                |> binary_part(0, 16)
                |> Base.encode16(case: :lower))

  @spec stream_id() :: String.t()
  def stream_id, do: @stream_id

  @doc "The crew as the live aggregate holds it now."
  @spec current() :: CrewState.t()
  def current, do: LiveState.of(__MODULE__, @stream_id)

  @impl true
  def state_module, do: CrewState

  @impl true
  def init(_stream_id), do: {:ok, CrewState.new()}

  @impl true
  def apply(state, event), do: CrewState.apply_event(state, event)

  @impl true
  def execute(state, %{command_type: :enlist_agent} = p),
    do: MaybeEnlistAgent.handle_payload(state, p)

  def execute(state, %{command_type: :discharge_agent} = p),
    do: MaybeDischargeAgent.handle_payload(state, p)

  def execute(state, %{command_type: :appoint_supervisor} = p),
    do: MaybeAppointSupervisor.handle_payload(state, p)

  def execute(state, %{command_type: :appoint_prioritiser} = p),
    do: MaybeAppointPrioritiser.handle_payload(state, p)

  def execute(state, %{command_type: :adopt_goal} = p),
    do: MaybeAdoptGoal.handle_payload(state, p)

  def execute(_state, _payload), do: {:error, :unknown_command}
end
