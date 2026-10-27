defmodule GuideCardLifecycle.OnCrewLeftDischargeCrew do
  # PM: a crew left the realm, so the board drops it: every agent of it is
  # discharged as the realm, and its operator seat is emptied (#40, threat
  # model R3) -- the discharge keeps the supervisor and an owner-appointed
  # prioritiser, so the seat is emptied on its own or an operator that is also
  # the supervisor could go on enlisting into the crew that left. A crew that
  # leaves may join again; that is a later admitted fact, and a later seq.
  @moduledoc false

  alias GuideCardLifecycle.CrewFacts.RealmActs

  @spec handle(map()) :: {:ok, map()}
  def handle(payload) do
    crew = payload["crew_id"]

    {:ok,
     %{discharged: RealmActs.discharge_crew(crew), seat: RealmActs.vacate_operator_seat(crew)}}
  end
end
