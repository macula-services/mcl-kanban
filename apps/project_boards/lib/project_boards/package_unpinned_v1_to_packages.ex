defmodule ProjectBoards.PackageUnpinnedV1ToPackages do
  # Projects package_unpinned_v1 into packages: the pin is gone, the rank stays.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [package_update: 3, project: 3]

  @impl true
  def interested_in, do: ["package_unpinned_v1"]

  @impl true
  def replay_policy, do: :deliver

  @impl true
  def init(_config), do: {:ok, %{}}

  @impl true
  def handle_event(type, envelope, _metadata, state) do
    with {:ok, _} <- project(type, envelope, &statements/2), do: {:ok, state}
  end

  defp statements(data, version), do: [package_update(data, version, [])]
end
