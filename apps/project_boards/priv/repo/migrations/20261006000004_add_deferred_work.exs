defmodule ProjectBoards.Repo.Migrations.AddDeferredWork do
  # Deferred work (#17): cards.deferred is 1 while the card, its package or
  # its board is deferred (the projections keep it current, so a query reads
  # one column and joins nothing); packages.deferred is the package's own
  # pause. A board's pause is bit 4 of boards.status.
  use Ecto.Migration

  def up do
    execute("ALTER TABLE cards ADD COLUMN deferred INTEGER NOT NULL DEFAULT 0")
    execute("ALTER TABLE packages ADD COLUMN deferred INTEGER NOT NULL DEFAULT 0")
  end

  def down do
    execute("ALTER TABLE packages DROP COLUMN deferred")
    execute("ALTER TABLE cards DROP COLUMN deferred")
  end
end
