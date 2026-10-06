defmodule GuideCardLifecycle.CardStatus do
  # A card's status, bit flags (#2): QUEUED 1, CLAIMED 2, BLOCKED 4,
  # FINISHED 8, WITHDRAWN 16, PINNED 32, DEFERRED 64 (#17: "not now", a state
  # with a reason, never a rank). Each desk computes the status after
  # its event and the event carries it, so the aggregate, the read model and
  # the wire all read the same number.
  @moduledoc false

  import Bitwise

  def queued, do: 1
  def claimed, do: 2
  def blocked, do: 4
  def finished, do: 8
  def withdrawn, do: 16
  def pinned, do: 32
  def deferred, do: 64

  def has?(status, flag), do: :evoq_bit_flags.has(status, flag)
  def pinned?(status), do: has?(status, pinned())

  @doc "Back in the queue: QUEUED instead of CLAIMED."
  def to_queue(status),
    do: status |> :evoq_bit_flags.unset(claimed()) |> :evoq_bit_flags.set(queued())

  @doc "Claimed: CLAIMED instead of QUEUED."
  def to_claimed(status),
    do: status |> :evoq_bit_flags.unset(queued()) |> :evoq_bit_flags.set(claimed())

  @doc "Closed as finished or withdrawn: only PINNED survives."
  def to_closed(status, flag), do: (status &&& pinned()) ||| flag

  @doc "The one word for where a card is."
  @spec state_name(non_neg_integer()) :: String.t()
  def state_name(status) do
    cond do
      has?(status, withdrawn()) -> "withdrawn"
      has?(status, finished()) -> "finished"
      has?(status, blocked()) -> "blocked"
      has?(status, claimed()) -> "claimed"
      has?(status, deferred()) -> "deferred"
      has?(status, queued()) -> "queued"
      true -> "unknown"
    end
  end
end
