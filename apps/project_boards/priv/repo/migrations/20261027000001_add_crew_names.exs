defmodule ProjectBoards.Repo.Migrations.AddCrewNames do
  # The name a crew is read under (#40 option b). A crew is acted on by its
  # KEY -- its crew_id for a crew the realm admitted, its name for a crew the
  # owner made -- so the roster's `crew` column holds keys. This table is the
  # one place a key is turned back into the name a person reads: one row per
  # admitted crew, written from crew_fact_observed_v1. A crew the owner made
  # has no row; its key is its name already.
  use Ecto.Migration

  def up do
    execute(
      "CREATE TABLE IF NOT EXISTS crew_names ( crew_id TEXT PRIMARY KEY, crew_name TEXT NOT NULL )"
    )
  end

  def down do
    execute("DROP TABLE IF EXISTS crew_names")
  end
end
