defmodule GuideCardLifecycle.BoardState do
  # One board per repo.
  @moduledoc false

  alias GuideCardLifecycle.BoardStatus

  defstruct [:board_id, :repo, status: 0]

  @type t :: %__MODULE__{board_id: String.t(), repo: String.t() | nil, status: non_neg_integer()}

  @spec new(String.t()) :: t()
  def new(board_id), do: %__MODULE__{board_id: board_id}

  def open?(%__MODULE__{status: s}), do: :evoq_bit_flags.has(s, BoardStatus.opened())
  def archived?(%__MODULE__{status: s}), do: :evoq_bit_flags.has(s, BoardStatus.archived())

  @spec apply_event(t(), map()) :: t()
  def apply_event(state, %{data: data, event_type: type}),
    do: apply_event(state, Map.put(data, :event_type, type))

  def apply_event(state, %{event_type: "board_opened_v1", repo: repo}),
    do: %{state | repo: repo, status: :evoq_bit_flags.set(state.status, BoardStatus.opened())}

  def apply_event(state, %{event_type: "board_archived_v1"}),
    do: %{state | status: :evoq_bit_flags.set(state.status, BoardStatus.archived())}

  def apply_event(state, _other), do: state
end
