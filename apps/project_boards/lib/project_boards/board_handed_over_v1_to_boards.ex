defmodule ProjectBoards.BoardHandedOverV1ToBoards do
  # Projects board_handed_over_v1 into boards: the board's new home crew (#29).
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [project: 3]

  @impl true
  def interested_in, do: ["board_handed_over_v1"]

  @impl true
  def replay_policy, do: :deliver

  @impl true
  def init(_config), do: {:ok, %{}}

  @impl true
  def handle_event(type, envelope, _metadata, state) do
    with {:ok, _} <- project(type, envelope, &statements/2), do: {:ok, state}
  end

  defp statements(data, _version),
    do: [{"UPDATE boards SET home_crew = ? WHERE board_id = ?", [data.home_crew, data.board_id]}]
end
