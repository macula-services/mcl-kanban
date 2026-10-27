defmodule GuideCardLifecycle.CrewFacts.CrewFactGate do
  # One crew fact at a time (mcl-kanban#40): every fact this board believes is
  # believed here, whether it came off its topic or out of the reconcile.
  #
  # The seq rule is read, act, then record, and six processes run it -- one
  # subscriber per fact, five of them, plus the reconciler. Two facts for one
  # crew meeting in that gap both pass the read: `admitted` at 5 enlists and
  # appoints while `revoked` at 6 records first, and the admitted one's record
  # is then refused as already observed -- so a revoked crew keeps the board,
  # and the reconcile, seeing the seq it expected, never asks again. The rule
  # is only true if nothing else is between its halves, so the whole path runs
  # inside this one process.
  #
  # What it costs is throughput this board does not need: facts about
  # different crews wait for each other for the length of a dispatch. What it
  # buys is that `seq` is a total order rather than a race.
  @moduledoc false

  use GenServer

  alias GuideCardLifecycle.CrewFacts
  alias GuideCardLifecycle.CrewFacts.CrewFact

  # One fact's whole path, and the caller waits for it: a subscriber that gave
  # up waiting would go on to read the next fact as if this one had not landed.
  @timeout_ms 30_000

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Believes one crew fact, once no other fact is being believed."
  @spec take(CrewFact.fact(), map()) :: {:ok, map()} | {:error, term()}
  def take(fact, wire), do: GenServer.call(__MODULE__, {:take, fact, wire}, @timeout_ms)

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:take, fact, wire}, _from, state),
    do: {:reply, CrewFacts.believe(fact, wire), state}
end
