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
  alias GuideCardLifecycle.CrewFacts.{CrewFact, CrewFactSubscriber, RealmSignature}
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
  What the service subscribes to: one topic per fact, a subscriber per topic.
  Empty while no realm key is configured, since nothing this board heard could
  be verified (and a boot with no key runs no mesh pool at all).
  """
  @spec subscriptions() :: [{String.t(), module(), term()}]
  def subscriptions do
    case RealmSignature.configured_key() do
      {:ok, _key} -> for(fact <- CrewFact.facts(), do: {topic(fact), CrewFactSubscriber, fact})
      {:error, _unset} -> []
    end
  end

  @doc """
  A crew fact off the wire, on the topic that names its `topic_fact`. Returns
  `{:ok, outcome}` when the board acted on it and `{:error, reason}` when it
  did not; `:already_observed` is the ordinary answer to a fact at a seq the
  board has already taken, from a replay or from the reconcile.
  """
  @spec received(String.t(), map()) :: {:ok, map()} | {:error, atom() | term()}
  def received(topic_fact, wire) do
    with {:ok, %{fact: fact} = read} <- CrewFact.read(wire),
         :ok <- named_on_its_topic(fact, topic_fact),
         :ok <- signed(read),
         :ok <- fresh(read) do
      act(read)
    end
  end

  defp named_on_its_topic(fact, fact), do: :ok
  defp named_on_its_topic(_fact, _topic_fact), do: {:error, :wrong_topic}

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
  defp act(%{fact: fact, payload: payload}) do
    with {:ok, outcome} <- Map.fetch!(@handlers, fact).handle(payload),
         {:ok, _version, _events} <- observed(fact, payload) do
      {:ok, outcome}
    end
  end

  defp observed(fact, payload) do
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
