defmodule GuideCardLifecycle.PackageState do
  # One work package: a GitHub issue labelled work-package that groups cards.
  # Packages are ranked on their own scale, ahead of the cards inside them.
  # A package follows the home crew of its repo's board (#29), copied onto
  # package_opened_v1; one opened before #29 belongs to the first crew.
  @moduledoc false

  alias GuideCardLifecycle.CrewName
  alias GuideCardLifecycle.PackageStatus

  defstruct [
    :package_id,
    :issue_ref,
    :title,
    :home_crew,
    :rank,
    :rationale,
    :ranked_by,
    status: 0
  ]

  @type t :: %__MODULE__{}

  @spec new(String.t()) :: t()
  def new(package_id), do: %__MODULE__{package_id: package_id}

  def open?(%__MODULE__{status: s}), do: :evoq_bit_flags.has(s, PackageStatus.opened())
  def pinned?(%__MODULE__{status: s}), do: :evoq_bit_flags.has(s, PackageStatus.pinned())
  def deferred?(%__MODULE__{status: s}), do: :evoq_bit_flags.has(s, PackageStatus.deferred())

  @spec apply_event(t(), map()) :: t()
  def apply_event(state, %{data: data, event_type: type}),
    do: apply_event(state, Map.put(data, :event_type, type))

  def apply_event(state, %{event_type: "package_opened_v1"} = e),
    do: %{
      state
      | issue_ref: e.issue_ref,
        title: e.title,
        home_crew: CrewName.home_crew_in(e),
        status: e.status
    }

  def apply_event(state, %{event_type: "package_prioritised_v1"} = e),
    do: %{state | rank: e.rank, rationale: e.rationale, ranked_by: e.by, status: e.status}

  def apply_event(state, %{event_type: "package_unpinned_v1"} = e),
    do: %{state | status: e.status}

  def apply_event(state, %{event_type: "package_deferred_v1"} = e),
    do: %{state | rank: nil, rationale: nil, ranked_by: nil, status: e.status}

  def apply_event(state, %{event_type: "package_resumed_v1"} = e),
    do: %{state | status: e.status}

  def apply_event(state, _other), do: state
end
