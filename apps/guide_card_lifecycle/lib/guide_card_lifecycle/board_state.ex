defmodule GuideCardLifecycle.BoardState do
  # One board per repo, with the crew it belongs to (#29): its home crew
  # orders its work, until the owner hands the board over to another. A board
  # opened before #29 names none and belongs to the first crew.
  @moduledoc false

  alias GuideCardLifecycle.BoardStatus
  alias GuideCardLifecycle.CrewName

  defstruct [:board_id, :repo, :home_crew, status: 0]

  @type t :: %__MODULE__{
          board_id: String.t(),
          repo: String.t() | nil,
          home_crew: String.t() | nil,
          status: non_neg_integer()
        }

  @spec new(String.t()) :: t()
  def new(board_id), do: %__MODULE__{board_id: board_id}

  def open?(%__MODULE__{status: s}), do: :evoq_bit_flags.has(s, BoardStatus.opened())
  def archived?(%__MODULE__{status: s}), do: :evoq_bit_flags.has(s, BoardStatus.archived())
  def deferred?(%__MODULE__{status: s}), do: :evoq_bit_flags.has(s, BoardStatus.deferred())

  @spec apply_event(t(), map()) :: t()
  def apply_event(state, %{data: data, event_type: type}),
    do: apply_event(state, Map.put(data, :event_type, type))

  def apply_event(state, %{event_type: "board_opened_v1", repo: repo} = e) do
    %{
      state
      | repo: repo,
        home_crew: CrewName.home_crew_in(e),
        status: :evoq_bit_flags.set(state.status, BoardStatus.opened())
    }
  end

  def apply_event(state, %{event_type: "board_handed_over_v1", home_crew: crew}),
    do: %{state | home_crew: crew}

  def apply_event(state, %{event_type: "board_archived_v1"}),
    do: %{state | status: :evoq_bit_flags.set(state.status, BoardStatus.archived())}

  def apply_event(state, %{event_type: "board_deferred_v1"}),
    do: %{state | status: :evoq_bit_flags.set(state.status, BoardStatus.deferred())}

  def apply_event(state, %{event_type: "board_resumed_v1"}),
    do: %{state | status: :evoq_bit_flags.unset(state.status, BoardStatus.deferred())}

  def apply_event(state, _other), do: state
end
