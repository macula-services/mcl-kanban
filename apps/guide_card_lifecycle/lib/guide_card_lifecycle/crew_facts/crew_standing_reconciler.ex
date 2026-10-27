defmodule GuideCardLifecycle.CrewFacts.CrewStandingReconciler do
  # The board's revocation bound (mcl-kanban#40, threat model R3): a fact is
  # the fast path, never the only one. Once at start and every 60 s, this asks
  # the realm for each crew the board knows -- `<realm>/_realm/_realm/identity/
  # crew_standing_v1` -- and feeds the answer through the SAME verifier and
  # highest-seq rule as a published fact. 60 s is therefore the bound the
  # issue states: a revoked crew loses the board within a minute, even if
  # every fact is missed. The tick is armed before the pass runs, so a slow
  # realm cannot stretch the period; it can only spend its own answers' time
  # inside one, and an unanswered call is worth nothing to revoke with anyway
  # (only a signed fact ends a crew).
  #
  # What it must never do is end a crew on anything but a signed fact, or on
  # the realm SAYING it does not know the crew (#40, Raf 2026-10-27). The
  # realm's other errors (`invalid_crew_id`), a lost answer and a timeout are
  # nothing at all, and a reconcile that read either as a revocation would
  # drop a healthy crew: they change nothing. An explicit `unknown_crew` is an
  # answer, so it is counted -- and only when the realm gives it
  # `@unknown_limit` times in a row for that crew, since one lost crew entry
  # at the realm is not a reason to empty a board. A signed fact in between
  # resets the count: the realm knows the crew after all.
  #
  # It runs only when a realm key is configured: with none, nothing this board
  # hears from a realm could be verified.
  @moduledoc false

  use GenServer

  require Logger

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewFacts
  alias GuideCardLifecycle.CrewFacts.RealmSignature
  alias GuideCardLifecycle.CrewState
  alias GuideCardLifecycle.DischargeCrew.{DischargeCrewV1, MaybeDischargeCrew}

  @period_ms 60_000
  @timeout_ms 5_000
  @version 1

  @doc """
  How many reconciles in a row a crew may be answered `unknown_crew` before
  the board discharges it. Three by default: a crew must be gone from the
  realm at three separate passes a minute apart, which no single bad answer
  can fake.
  """
  @spec unknown_limit() :: pos_integer()
  def unknown_limit, do: Application.get_env(:mcl_om, :crew_unknown_limit, 3)

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    case RealmSignature.configured_key() do
      {:ok, _key} ->
        Process.send_after(self(), :reconcile, 0)
        {:ok, %{counts: %{}}}

      {:error, _unset} ->
        :ignore
    end
  end

  @impl true
  def handle_info(:reconcile, %{counts: counts} = state) do
    Process.send_after(self(), :reconcile, @period_ms)
    {:noreply, %{state | counts: reconcile(&ask/1, counts)}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @doc """
  One pass over the crews this board knows, carrying `counts` -- for each crew,
  how many reconciles in a row the realm has answered `unknown_crew` for it,
  and the seq the board held when that count was taken. Every crew id it holds
  is asked about; a crew whose standing the realm answers with its latest
  signed fact is acted on by seq, exactly as if that fact had been published,
  and a crew answered `unknown_crew` `unknown_limit/0` times in a row is
  discharged.

  The seq is carried with the count because a signed fact resets it whether it
  arrived here or on the crew's own topic: a fact the board accepted moved the
  seq, and the count cannot survive that.

  `fetch` asks the realm about one crew id and is the mesh in production; a
  test hands its own reply, which is the only way to check what the board does
  with a realm that answers.
  """
  @spec reconcile((String.t() -> {:ok, term()} | {:error, term()}), map()) :: map()
  def reconcile(fetch \\ &ask/1, counts \\ %{}) do
    live = CrewAggregate.current()

    Enum.reduce(CrewState.live_crews(live), counts, fn {crew_id, name}, counts ->
      crew_id |> fetch.() |> standing(name) |> counted(counts, crew_id, live)
    end)
  end

  @doc "The procedure a crew's standing is asked at, in this board's realm."
  @spec procedure() :: String.t()
  def procedure,
    do: :macula_topic.realm_hope(CrewFacts.realm_name(), "identity", "crew_standing", @version)

  # Direct-dial, like the realm's other identity procedures (macula-realm#107).
  defp ask(crew_id) do
    with {:ok, pool, realm} <- :mcl_om.mesh_handles(),
         do: :macula.call(pool, realm, procedure(), %{"crew_id" => crew_id}, @timeout_ms)
  end

  # The realm's reply is its latest fact: the fact name beside the signed
  # payload it was published with. That is the same pair a topic gives a
  # subscriber -- the name outside the payload, the payload as it was signed --
  # so it takes the one path, under the same gate. The envelope is read in
  # every spelling it may arrive in (keys as CBOR text, atoms or strings, and
  # a name that is itself text-wrapped), because a name this board cannot read
  # is a revocation it never applies; the payload inside is the topic fact's
  # wire shape, and is taken as it is.
  defp standing({:ok, reply}, name) when is_map(reply) do
    fact = reply |> field("fact") |> text()
    payload = field(reply, "payload")

    if is_binary(fact) and is_map(payload) do
      CrewFacts.received(fact, payload) |> taken(name)
    else
      kept(name, reply)
    end
  end

  # The one answer that stands against a crew: the realm's own `unknown_crew`.
  # It counts only when the realm says it, never when the call failed to reach
  # it, and never for any other reason.
  defp standing({:error, why}, name) when why in ["unknown_crew", :unknown_crew] do
    Logger.warning("crew_standing for #{name}: the realm does not know the crew")
    :unknown
  end

  defp standing(reply, name), do: kept(name, reply)

  # A fact the board believed, and one it already holds, are both a signed
  # fact between two counts: either way the realm knows the crew.
  defp taken({:ok, _outcome}, _name), do: :fact
  defp taken({:error, :already_observed}, _name), do: :fact
  defp taken({:error, reason}, name), do: kept(name, reason)

  defp field(reply, "fact"),
    do: Map.get(reply, "fact") || Map.get(reply, {:text, "fact"}) || Map.get(reply, :fact)

  defp field(reply, "payload"),
    do:
      Map.get(reply, "payload") || Map.get(reply, {:text, "payload"}) || Map.get(reply, :payload)

  defp text({:text, name}) when is_binary(name), do: name
  defp text(name), do: name

  # What one answer means for the count: a signed fact the board believed, or
  # already held, RESETS it; the realm SAYING it does not know the crew is the
  # one answer that counts against it; everything else -- a timeout, a lost
  # answer, `invalid_crew_id`, an envelope this board cannot read -- is not an
  # answer about the crew at all and leaves the count exactly where it was.
  defp counted(:fact, counts, crew_id, _live), do: Map.delete(counts, crew_id)

  defp counted(:unknown, counts, crew_id, live) do
    seq = CrewState.crew_seq(live, crew_id)
    count = consecutive(counts, crew_id, seq) + 1

    if count >= unknown_limit(),
      do: discharge(crew_id, count, counts),
      else: Map.put(counts, crew_id, %{count: count, seq: seq})
  end

  defp counted(:kept, counts, _crew_id, _live), do: counts

  # A count only stands while the board's seq has not moved: a fact accepted
  # since it was taken -- off the crew's own topic, which this pass never sees
  # -- makes the realm's next answer the first of a new run, not the second.
  defp consecutive(counts, crew_id, seq) do
    case Map.get(counts, crew_id) do
      %{count: count, seq: ^seq} -> count
      _none_or_a_fact_since -> 0
    end
  end

  defp discharge(crew_id, count, counts) do
    case DischargeCrewV1.new(%{crew: crew_id, reason: "unknown_crew_after_n", by: Actor.board()}) do
      {:ok, cmd} -> discharged(crew_id, count, cmd)
      {:error, reason} -> left(crew_id, reason)
    end

    Map.delete(counts, crew_id)
  end

  defp discharged(crew_id, count, cmd) do
    Logger.warning(
      "crew_standing for #{crew_id}: the realm answered unknown_crew #{count} times in a " <>
        "row, so the board discharged the crew"
    )

    case MaybeDischargeCrew.dispatch(cmd) do
      {:ok, _version, _events} -> :ok
      {:error, reason} -> left(crew_id, reason)
    end
  end

  defp left(crew_id, why) do
    Logger.warning("crew_standing for #{crew_id} could not discharge the crew: #{inspect(why)}")
    :error
  end

  defp kept(name, why) do
    Logger.warning("crew_standing for #{name} left the board as it is: #{inspect(why)}")
    :kept
  end
end
