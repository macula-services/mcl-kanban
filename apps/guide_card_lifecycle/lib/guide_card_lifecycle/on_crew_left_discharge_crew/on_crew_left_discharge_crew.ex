defmodule GuideCardLifecycle.OnCrewLeftDischargeCrew do
  # PM: a crew left the realm, so the board drops it: every agent of it is
  # discharged as the realm (#40, threat model R3). A crew that leaves may
  # join again; that is a later admitted fact, and a later seq.
  @moduledoc false

  alias GuideCardLifecycle.CrewFacts.RealmActs

  @spec handle(map()) :: {:ok, map()}
  def handle(payload), do: {:ok, %{discharged: RealmActs.discharge_crew(payload["crew_name"])}}
end
