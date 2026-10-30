defmodule GuideCardLifecycle.CrewFacts do
  # The board's consumer of the realm's crew facts (mcl-kanban#40; contract in
  # macula-realm#107's threat model, R3/R4/R7).
  #
  # One path for both halves: a fact off a `<realm>/_realm/_realm/crew/
  # <fact>_v1` topic, and the same fact fetched from `identity.crew_standing`
  # by the reconcile. Read the shape, check the signature against the pinned
  # realm key, keep the highest seq per crew_id, act through the PM for that
  # fact, and only then record that the fact was observed.
  #
  # Nothing here reads who published anything: a topic's publish right is
  # checked at the publisher's ingress station, not against a station that
  # colludes, so the signature is the whole authority (R4).
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewFacts.{CrewFact, CrewFactGate, CrewFactSubscriber, RealmSignature}
  alias GuideCardLifecycle.CrewState
  alias GuideCardLifecycle.ObserveCrewFact.{MaybeObserveCrewFact, ObserveCrewFactV1}

  alias GuideCardLifecycle.{
    OnCrewAdmittedAppointOperator,
    OnCrewLeftDischargeCrew,
    OnCrewOperatorReplacedAppointOperator,
    OnCrewRevokedDischargeCrew,
    OnCrewSuspendedDischargeCrew
  }

  @handlers %{
    "admitted" => OnCrewAdmittedAppointOperator,
    "operator_replaced" => OnCrewOperatorReplacedAppointOperator,
    "suspended" => OnCrewSuspendedDischargeCrew,
    "revoked" => OnCrewRevokedDischargeCrew,
    "left" => OnCrewLeftDischargeCrew
  }

  @doc "The realm this board belongs to, as a topic names it."
  @spec realm_name() :: String.t()
  def realm_name, do: Application.get_env(:mcl_om, :realm_name, "io.macula")

  @doc "The topic one crew fact is published on, in this board's realm."
  @spec topic(CrewFact.fact()) :: String.t()
  def topic(fact), do: CrewFact.topic(realm_name(), fact)

  @doc """
  What the service subscribes to: one topic per fact, a subscriber per topic,
  each declaring `sources => members` -- macula 18 refuses a subscription that
  names no source (macula#147), and the producer here is the realm itself,
  which is a member of the realm it serves.

  Empty while no realm key is configured, since nothing this board heard could
  be verified (and a boot with no key runs no mesh pool at all); `members` is
  also refused outright in a pool that pinned no realm key, so the two agree.
  """
  @spec subscriptions() :: [map()]
  def subscriptions do
    case RealmSignature.configured_key() do
      {:ok, _key} ->
        for fact <- CrewFact.facts(),
            do: %{topic: topic(fact), module: CrewFactSubscriber, args: fact, sources: :members}

      {:error, _unset} ->
        []
    end
  end

  @doc """
  A crew fact off the wire, on the topic that names it. Returns
  `{:ok, outcome}` when the board acted on it and `{:error, reason}` when it
  did not; `:already_observed` is the ordinary answer to a fact at a seq the
  board has already taken, from a replay or from the reconcile.

  It is believed one at a time (CrewFactGate): the read, the act and the
  record are one step, so two facts for one crew cannot both read the seq
  they are replacing.
  """
  @spec received(CrewFact.fact(), map()) :: {:ok, map()} | {:error, term()}
  def received(fact, wire), do: CrewFactGate.take(fact, wire)

  @doc """
  The path itself, already inside the gate: read, verify against the pinned
  realm key, compare the seq, act, record. Public only because the gate is
  its own module -- nothing else may call it, or the seq rule has a second
  racer.
  """
  @spec believe(CrewFact.fact(), map()) :: {:ok, map()} | {:error, term()}
  def believe(fact, wire) do
    with {:ok, read} <- CrewFact.read(fact, wire),
         :ok <- signed(read),
         :ok <- fresh(read) do
      act(read)
    end
  end

  # A crew is acted on by its ID (#40 option b): its agents, its operator and
  # its seq are held under the `crew_id` the realm signed, so two crews the
  # realm admitted under one name are two crews here too, and a drop for one
  # can no longer discharge the other's agents.
  #
  # The NAME the fact carries is what a person reads, and it is recorded with
  # the seq (crew_fact_observed_v1) so the board can show it and the reconcile
  # can say which crew it kept. It is not a key and nothing is refused for it:
  # the realm's invite does not check its names against each other, and the
  # board no longer has to.
  defp signed(%{fact: fact, payload: payload, signature: signature}) do
    with {:ok, key} <- RealmSignature.configured_key(),
         do: RealmSignature.verify(CrewFact.signed_bytes(fact, payload), signature, key)
  end

  # The highest seq per crew id wins: an equal or lower one is a replay, and a
  # replayed old `admitted` must never re-appoint a crew that has since been
  # revoked.
  defp fresh(%{payload: %{"crew_id" => crew_id, "seq" => seq}}) do
    if seq > CrewState.crew_seq(CrewAggregate.current(), crew_id),
      do: :ok,
      else: {:error, :already_observed}
  end

  # Act, then record: a crash between the two replays the fact, and every act
  # here refuses what it has already done. Recording first would lose the act
  # instead, and the reconcile would have to notice.
  #
  # What was left undone decides whether the seq is recorded at all, because
  # the record is what stops the reconcile asking about this crew again. A
  # refusal the board's own rule named -- :name_taken, :held_in_another_crew
  # -- is the board's answer and will not change by asking, so the fact is
  # recorded and the refusal is reported with it. Anything the desk did not
  # name (RealmActs wraps those as :not_an_answer: a store that was not there,
  # a timeout) is the board failing rather than the board deciding: nothing is
  # recorded, and the next reconcile pass asks again.
  defp act(%{fact: fact, payload: payload}) do
    case Map.fetch!(@handlers, fact).handle(payload) do
      {:ok, outcome} -> settle(fact, payload, outcome, undone(outcome))
      {:error, reason} -> {:error, reason}
    end
  end

  defp settle(fact, payload, outcome, []), do: observed(fact, payload, outcome)

  defp settle(fact, payload, outcome, refusals) do
    if Enum.all?(refusals, fn {_what, why} -> final?(why) end),
      do: observed(fact, payload, outcome),
      else: {:error, {:left_undone, refusals}}
  end

  # An act the desk would not do, and the reason it gave: a single act's
  # result, or one per agent for the acts that walk a crew.
  defp undone(outcome),
    do: Enum.flat_map(outcome, fn {what, value} -> refused(what, value) end)

  defp refused(what, {:error, reason}), do: [{what, reason}]

  defp refused(what, acts) when is_list(acts),
    do: for({node, {:error, why}} <- acts, do: {{what, node}, why})

  defp refused(_what, _done), do: []

  # An answer from the board, whatever it says; a failure is not one.
  defp final?({:not_an_answer, _reason}), do: false
  defp final?(_answer), do: true

  defp observed(fact, payload, outcome) do
    with {:ok, _version, _events} <- dispatch(fact, payload), do: {:ok, outcome}
  end

  defp dispatch(fact, payload) do
    with {:ok, command} <-
           ObserveCrewFactV1.new(%{
             crew_id: payload["crew_id"],
             crew_name: payload["crew_name"],
             fact: fact,
             seq: payload["seq"],
             by: Actor.realm()
           }),
         do: MaybeObserveCrewFact.dispatch(command)
  end
end
