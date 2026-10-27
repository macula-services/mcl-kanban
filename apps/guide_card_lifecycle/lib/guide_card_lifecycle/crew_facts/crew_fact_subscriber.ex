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

  @impl true
  def handle_event(_topic, payload, _meta, fact) when is_map(payload) do
    report(fact, CrewFacts.received(fact, payload))
    {:noreply, fact}
  end

  def handle_event(_topic, _payload, _meta, fact), do: {:noreply, fact}

  # A fact at a seq already taken is the ordinary replay path, not noise.
  defp report(_fact, {:ok, _outcome}), do: :ok
  defp report(_fact, {:error, :already_observed}), do: :ok

  defp report(fact, {:error, reason}),
    do: Logger.warning("crew fact #{fact} left the board as it is: #{inspect(reason)}")
end
