defmodule ProjectBoards.CardFiledV1ToCards do
  # Projects card_filed_v1 into cards: the package, and the package's rank as
  # the packages table holds it now (package_prioritised_v1 keeps it current).
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [project: 3]

  @impl true
  def interested_in, do: ["card_filed_v1"]

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
      {"UPDATE cards SET work_package = ?, package_rank = (SELECT rank FROM packages WHERE issue_ref = ?), " <>
         "status = ?, changed_at = ?, version = ? WHERE card_id = ? AND version < ?",
       [
         data.work_package,
         data.work_package,
         data.status,
         data.at,
         version,
         data.card_id,
         version
       ]}
    ]
end
