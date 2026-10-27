defmodule GuideCardLifecycle.OnCrewRevokedDischargeCrew do
  # PM: the realm revoked a crew, wholesale or through its operator, so the
  # board drops it: every agent of it is discharged as the realm (#40, threat
  # model R3). A fact is the fast path; the reconcile is the backstop for the
  # one this board never hears.
  @moduledoc false

  alias GuideCardLifecycle.CrewFacts.RealmActs

  @spec handle(map()) :: {:ok, map()}
  def handle(payload), do: {:ok, %{discharged: RealmActs.discharge_crew(payload["crew_id"])}}
end
