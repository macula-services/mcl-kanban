defmodule ProjectBoards.Repo.Migrations.AddHomeCrewsAndCrewLanes do
  # Home crews and crew lanes (#29). `boards.home_crew` is the crew a board
  # belongs to; the default gives every board opened before this the first
  # crew, the same as its aggregate reads it. `cards.lane_crew` is the crew a
  # card is reserved for, beside `lane_node_id` for an agent's lane.
  use Ecto.Migration

  def up do
    execute("ALTER TABLE boards ADD COLUMN home_crew TEXT NOT NULL DEFAULT 'home'")
    execute("ALTER TABLE cards ADD COLUMN lane_crew TEXT")
  end

  def down do
    execute("ALTER TABLE cards DROP COLUMN lane_crew")
    execute("ALTER TABLE boards DROP COLUMN home_crew")
  end
end
