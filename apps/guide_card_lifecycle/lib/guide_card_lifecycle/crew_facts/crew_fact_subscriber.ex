defmodule GuideCardLifecycle.CrewFacts.CrewFactSubscriber do
  # The `macula_subscriber` for one crew fact's topic (#40): it hands the fact
  # to CrewFacts, which verifies it, keeps the highest seq and acts. Its Args
  # are the fact the topic carries, so a fact published on another fact's
  # topic is refused rather than believed.
  #
  # Payloads arrive in WIRE FORM, which is exactly what CrewFacts.received/2
  # reads; nothing is normalized here, or the signed bytes could not be rebuilt.
  @moduledoc false

  @behaviour :macula_subscriber

  require Logger

  alias GuideCardLifecycle.CrewFacts

  @impl true
  def init(fact) when is_binary(fact), do: {:ok, fact}

  # A subscription that names no fact could never accept one: every event would
  # be refused as another fact's. Stop here rather than run a subscriber that
  # can only say no; CrewFacts.subscriptions/0 always names one, so this is a
  # wiring mistake, and not one to leave running quietly.
  def init(no_fact), do: {:stop, {:no_fact_named, no_fact}}

  @impl true
  def handle_event(_topic, payload, _meta, fact) when is_map(payload) do
    _ = report(fact, CrewFacts.received(fact, payload))
    {:noreply, fact}
  end

  def handle_event(_topic, _payload, _meta, fact), do: {:noreply, fact}

  # A fact at a seq already taken is the ordinary replay path, not noise. An
  # act the desk refused is not noise either: the fact was believed and the
  # board could not do all of it, so it is said out loud with what was left.
  defp report(fact, {:ok, outcome}), do: refusal(fact, outcome)
  defp report(_fact, {:error, :already_observed}), do: :ok

  # The realm lets two crews share one name; this board cannot, because a crew
  # is held by its agents' name. Say so in the terms the realm's admin can act
  # on, and say what was done: nothing, and no seq recorded.
  defp report(fact, {:error, {:crew_name_taken, name}}) do
    Logger.warning(
      "crew fact #{fact} was not acted on: this board already holds a crew named " <>
        "#{inspect(name)} under another crew id, and a board keys a crew by name. " <>
        "Nothing was enlisted, appointed or discharged for it. Invite this crew under another name."
    )
  end

  defp report(fact, {:error, reason}),
    do: Logger.warning("crew fact #{fact} left the board as it is: #{inspect(reason)}")

  defp refusal(fact, outcome) do
    for {what, why} <- Enum.flat_map(outcome, fn {what, value} -> refusals(what, value) end) do
      Logger.warning("crew fact #{fact}: #{what} left undone: #{inspect(why)}")
    end
  end

  defp refusals(what, {:error, reason}), do: [{what, reason}]

  defp refusals(what, acts) when is_list(acts),
    do: for({node, {:error, why}} <- acts, do: {what, {node, why}})

  defp refusals(_what, _done), do: []
end
