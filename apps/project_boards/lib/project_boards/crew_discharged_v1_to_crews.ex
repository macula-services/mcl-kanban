defmodule ProjectBoards.CrewDischargedV1ToCrews do
  # Projects crew_discharged_v1 into crews: the board dropped a crew the realm
  # stopped knowing (#40), so the crew's operator seat is empty. Without this
  # the row keeps naming the agent that sat there, and a crew the board no
  # longer knows still shows an operator -- the realm answers `unknown_crew`
  # for it on every reconcile, so the drop repeats and the stale seat would
  # stay for as long as the crew is gone.
  #
  # The row is not inserted, for the reason operator_seat_vacated_v1_to_crews
  # gives: a seat exists only on a row an appointment made. The roles string is
  # recomputed from the same statements so the agent stops reading as operator.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [project: 3]

  alias ProjectBoards.Projection

  @impl true
  def interested_in, do: ["crew_discharged_v1"]

  @impl true
  def replay_policy, do: :deliver

  @impl true
  def init(_config), do: {:ok, %{}}

  @impl true
  def handle_event(type, envelope, _metadata, state) do
    with {:ok, _} <- project(type, envelope, &statements/2), do: {:ok, state}
  end

  defp statements(data, _version) do
    [
      {"UPDATE crews SET operator_node_id = NULL WHERE name = ?", [data.crew]},
      Projection.roles_sql()
    ]
  end
end
