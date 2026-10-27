defmodule GuideCardLifecycle.OnCrewRevokedDischargeCrew do
  # PM: the realm revoked a crew, wholesale or through its operator, so the
  # board drops it: every agent of it is discharged as the realm, and its
  # operator seat is emptied (#40, threat model R3). The seat is emptied
  # separately because the discharge lets the supervisor and an
  # owner-appointed prioritiser stay: without it, an operator that is also the
  # supervisor would go on enlisting into the revoked crew. A fact is the fast
  # path; the reconcile is the backstop for the one this board never hears.
  @moduledoc false

  alias GuideCardLifecycle.CrewFacts.RealmActs

  @spec handle(map()) :: {:ok, map()}
  def handle(payload) do
    crew = payload["crew_id"]

    {:ok,
     %{discharged: RealmActs.discharge_crew(crew), seat: RealmActs.vacate_operator_seat(crew)}}
  end
end
