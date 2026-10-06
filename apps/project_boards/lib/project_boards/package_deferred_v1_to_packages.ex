defmodule ProjectBoards.PackageDeferredV1ToPackages do
  # Projects package_deferred_v1 into packages and its cards: paused and unranked, so its cards are deferred and carry no package rank.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [deferred: 2, package_update: 3, project: 3]

  @impl true
  def interested_in, do: ["package_deferred_v1"]

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
        {"rank", nil},
        {"rationale", nil},
        {"ranked_by", nil},
        {"deferred", 1}
      ]),
      {"UPDATE cards SET package_rank = NULL WHERE work_package = ?", [data.issue_ref]},
      deferred("work_package = ?", [data.issue_ref])
    ]
end
