defmodule QueryBoards.GetCrew.GetCrew do
  # get_crew: every enlisted agent with its roles.
  @moduledoc false

  alias QueryBoards.ReadModel

  @spec get_crew() :: [map()]
  def get_crew do
    "SELECT node_id, name, roles, enlisted_at FROM crew ORDER BY name"
    |> ReadModel.q([])
    |> Enum.map(fn [node_id, name, roles, at] ->
      %{node_id: node_id, name: name, roles: String.split(roles, ","), enlisted_at: at}
    end)
  end
end
