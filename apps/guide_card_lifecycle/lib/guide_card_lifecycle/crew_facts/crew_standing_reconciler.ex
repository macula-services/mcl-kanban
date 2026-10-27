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
  # What it must never do is end a crew on anything but a signed fact. The
  # realm's errors (`unknown_crew`, `invalid_crew_id`) are unsigned, a lost
  # answer is nothing at all, and a reconcile that read either as a revocation
  # would drop a healthy crew. All of them leave the board exactly as it is
  # and are retried at the next tick.
  #
  # It runs only when a realm key is configured: with none, nothing this board
  # hears from a realm could be verified.
  @moduledoc false

  use GenServer

  require Logger

  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewFacts
  alias GuideCardLifecycle.CrewFacts.RealmSignature
  alias GuideCardLifecycle.CrewState

  @period_ms 60_000
  @timeout_ms 5_000
  @version 1

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    case RealmSignature.configured_key() do
      {:ok, _key} ->
        Process.send_after(self(), :reconcile, 0)
        {:ok, %{}}

      {:error, _unset} ->
        :ignore
    end
  end

  @impl true
  def handle_info(:reconcile, state) do
    Process.send_after(self(), :reconcile, @period_ms)
    reconcile()
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @doc """
  One pass over the crews this board knows. Every crew id it holds is asked
  about; a crew whose standing the realm answers with its latest signed fact
  is acted on by seq, exactly as if that fact had been published.

  `fetch` asks the realm about one crew id and is the mesh in production; a
  test hands its own reply, which is the only way to check what the board does
  with a realm that answers.
  """
  @spec reconcile((String.t() -> {:ok, term()} | {:error, term()})) :: :ok
  def reconcile(fetch \\ &ask/1) do
    for {crew_id, name} <- CrewState.admitted_crews(CrewAggregate.current()) do
      _ = crew_id |> fetch.() |> standing(name)
    end

    :ok
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
  # so it takes the one path, under the same gate. The envelope's own keys are
  # read either way they may arrive (the realm's reply writes them as CBOR
  # text, and a decoded reply may come back atom-keyed); the payload inside is
  # the topic fact's wire shape, and is taken as it is.
  defp standing({:ok, reply}, name) when is_map(reply) do
    fact = field(reply, "fact")
    payload = field(reply, "payload")

    if is_binary(fact) and is_map(payload) do
      CrewFacts.received(fact, payload) |> taken(name)
    else
      kept(name, reply)
    end
  end

  defp standing(reply, name), do: kept(name, reply)

  defp field(reply, "fact"),
    do: Map.get(reply, "fact") || Map.get(reply, {:text, "fact"}) || Map.get(reply, :fact)

  defp field(reply, "payload"),
    do:
      Map.get(reply, "payload") || Map.get(reply, {:text, "payload"}) || Map.get(reply, :payload)

  defp taken({:ok, outcome}, _name), do: outcome
  defp taken({:error, :already_observed}, _name), do: :current
  defp taken({:error, reason}, name), do: kept(name, reason)

  defp kept(name, why) do
    Logger.warning("crew_standing for #{name} left the board as it is: #{inspect(why)}")
    {:error, why}
  end
end
