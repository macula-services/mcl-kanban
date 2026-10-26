defmodule ProjectBoards.AgentEnlistedV1ToCrew do
  # Projects agent_enlisted_v1 into crew.
  #
  # The insert writes roles 'agent' and then recomputes them (#28): the row
  # must agree with the crews table whatever order the handlers ran in. The
  # owner's one-step "enlist as operator" emits agent_enlisted_v1 and then
  # operator_appointed_v1 through two handlers, and the operator one may land
  # first — it would find no row to recompute, and the insert would then write
  # roles without ',operator' until the next appointment.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [project: 3]

  alias ProjectBoards.Projection

  @impl true
  def interested_in, do: ["agent_enlisted_v1"]

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
      {"INSERT OR REPLACE INTO crew (node_id, name, supervisor, prioritiser, crew, roles, enlisted_at) VALUES (?, ?, 0, 0, ?, 'agent', ?)",
       [data.node_id, data.name, crew_in(data), data.at]},
      Projection.roles_sql()
    ]
  end

  # An agent enlisted before #28 carries no crew in its event: it belongs to
  # the home crew. The event is left as it was.
  defp crew_in(%{crew: crew}) when is_binary(crew), do: crew
  defp crew_in(_data), do: GuideCardLifecycle.CrewName.home()
end
