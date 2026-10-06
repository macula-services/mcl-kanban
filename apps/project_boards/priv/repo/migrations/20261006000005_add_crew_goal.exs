defmodule ProjectBoards.Repo.Migrations.AddCrewGoal do
  # The crew's one goal (#18): one row, and the one or two packages it covers
  # in a table of their own, so the next-card query orders on them without
  # parsing anything.
  use Ecto.Migration

  def up do
    execute(
      "CREATE TABLE crew_goal (id INTEGER PRIMARY KEY CHECK (id = 1), goal TEXT NOT NULL, " <>
        "adopted_by TEXT, adopted_at INTEGER NOT NULL)"
    )

    execute("CREATE TABLE crew_goal_packages (ref TEXT PRIMARY KEY)")
  end

  def down do
    execute("DROP TABLE crew_goal_packages")
    execute("DROP TABLE crew_goal")
  end
end
