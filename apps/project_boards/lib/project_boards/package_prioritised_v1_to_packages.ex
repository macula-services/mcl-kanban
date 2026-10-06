defmodule ProjectBoards.PackagePrioritisedV1ToPackages do
  # Projects package_prioritised_v1 into packages, and copies the rank onto
  # every card filed in the package (cards.package_rank), so a query orders
  # cards by package without a join.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [package_update: 3, project: 3]

  @impl true
  def interested_in, do: ["package_prioritised_v1"]

  @impl true
  def replay_policy, do: :deliver

  @impl true
  def init(_config), do: {:ok, %{}}

  @impl true
  def handle_event(type, envelope, _metadata, state) do
    with {:ok, _} <- project(type, envelope, &statements/2), do: {:ok, state}
  end

  defp statements(data, version),
    do: [
      package_update(data, version, [
        {"rank", data.rank},
        {"rationale", data.rationale},
        {"ranked_by", data[:by]}
      ]),
      {"UPDATE cards SET package_rank = (SELECT rank FROM packages WHERE package_id = ?) WHERE work_package = ?",
       [data.package_id, data.issue_ref]}
    ]
end
