defmodule ProjectBoards.OperatorSeatVacatedV1ToCrews do
  # Projects operator_seat_vacated_v1 into crews: the crew's operator seat is
  # empty (#40). The row is not inserted -- a seat exists only on a row an
  # appointment made -- and the roles string is recomputed so the agent that
  # sat there stops reading as operator.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [project: 3]

  alias ProjectBoards.Projection

  @impl true
  def interested_in, do: ["operator_seat_vacated_v1"]

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
