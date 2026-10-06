defmodule ProjectBoards.PackageOpenedV1ToPackages do
  # Projects package_opened_v1 into packages: a new row, unranked.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [project: 3]

  @impl true
  def interested_in, do: ["package_opened_v1"]

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
      {"INSERT OR IGNORE INTO packages (package_id, issue_ref, title, pinned, opened_by, opened_at, version) VALUES (?, ?, ?, 0, ?, ?, ?)",
       [data.package_id, data.issue_ref, data.title, data[:by], data.at, version]}
    ]
end
