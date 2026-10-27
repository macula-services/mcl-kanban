defmodule GuideCardLifecycle.OnCrewSuspendedDischargeCrew do
  # PM: the realm suspended a crew -- its operator resigned or its membership
  # reached its end -- so the board drops the crew: every agent of it is
  # discharged as the realm, and its operator seat is emptied (#40, threat
  # model R3) -- the discharge keeps the supervisor and an owner-appointed
  # prioritiser, so the seat goes on its own or an operator that is also the
  # supervisor could go on enlisting into the suspended crew. The reason the
  # fact carries does not change the act; a suspended crew may be admitted
  # again, and that is a later fact.
  @moduledoc false

  alias GuideCardLifecycle.CrewFacts.RealmActs

  @spec handle(map()) :: {:ok, map()}
  def handle(payload) do
    crew = payload["crew_id"]

    {:ok,
     %{discharged: RealmActs.discharge_crew(crew), seat: RealmActs.vacate_operator_seat(crew)}}
  end
end
