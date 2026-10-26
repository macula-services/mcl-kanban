defmodule ProjectBoards.OperatorAppointedV1ToCrews do
  # Projects operator_appointed_v1 into crews: one operator per crew, replaced
  # on reappointment, and the roles string of the roster recomputed so the
  # agent's row says operator without a second source of truth (#28).
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [project: 3]

  alias ProjectBoards.Projection

  @impl true
  def interested_in, do: ["operator_appointed_v1"]

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
      {"INSERT INTO crews (name, operator_node_id) VALUES (?, ?) " <>
         "ON CONFLICT(name) DO UPDATE SET operator_node_id = excluded.operator_node_id",
       [data.crew, data.node_id]},
      Projection.roles_sql()
    ]
  end
end
