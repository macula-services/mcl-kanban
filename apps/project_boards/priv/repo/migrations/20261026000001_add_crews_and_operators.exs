defmodule ProjectBoards.Repo.Migrations.AddCrewsAndOperators do
  # Crews and their operators (#28). `crew.crew` is the crew an agent is
  # enlisted into; the default gives every agent enlisted before this the home
  # crew, without touching the events that recorded them. `crews` is the
  # operator of each crew: one row per crew, replaced on reappointment.
  use Ecto.Migration

  def up do
    execute("ALTER TABLE crew ADD COLUMN crew TEXT NOT NULL DEFAULT 'home'")
    execute("CREATE TABLE IF NOT EXISTS crews ( name TEXT PRIMARY KEY, operator_node_id TEXT )")
    execute("INSERT OR IGNORE INTO crews (name) VALUES ('home')")
  end

  def down do
    execute("DROP TABLE IF EXISTS crews")
    execute("ALTER TABLE crew DROP COLUMN crew")
  end
end
