defmodule ProjectBoards.CrewFactObservedV1ToCrewNames do
  # Projects crew_fact_observed_v1 into crew_names: the name the realm
  # admitted a crew under, keyed by the crew id the board acts on (#40 option
  # b). The roster holds keys, so this is what get_crew reads to show a person
  # a name again -- and the crews the realm knows by one name are still two
  # rows here, told apart by their ids.
  #
  # A crew the owner made has no row at all: its key is its name already.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [project: 3]

  @impl true
  def interested_in, do: ["crew_fact_observed_v1"]

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
      {"INSERT INTO crew_names (crew_id, crew_name) VALUES (?, ?) " <>
         "ON CONFLICT(crew_id) DO UPDATE SET crew_name = excluded.crew_name",
       [data.crew_id, data.crew_name]}
    ]
  end
end
