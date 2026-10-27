defmodule GuideCardLifecycle.OnCrewSuspendedDischargeCrew do
  # PM: the realm suspended a crew -- its operator resigned or its membership
  # reached its end -- so the board drops the crew: every agent of it is
  # discharged as the realm (#40, threat model R3). The reason the fact
  # carries does not change the act; a suspended crew may be admitted again,
  # and that is a later fact.
  @moduledoc false

  alias GuideCardLifecycle.CrewFacts.RealmActs

  @spec handle(map()) :: {:ok, map()}
  def handle(payload), do: {:ok, %{discharged: RealmActs.discharge_crew(payload["crew_name"])}}
end
