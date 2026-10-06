defmodule ProjectBoards.Repo.Migrations.AddWorkPackages do
  # Work packages (#9): the packages table, and each card's package, the
  # package's rank (copied, so a query orders without a join) and when the
  # card was ranked. v0.2.0 created these from code before the read model had
  # migrations, so a column that is already there is left alone.
  use Ecto.Migration

  @card_columns [ranked_at: "INTEGER", work_package: "TEXT", package_rank: "INTEGER"]

  def up do
    present = columns("cards")

    for {name, type} <- @card_columns, Atom.to_string(name) not in present,
        do: execute("ALTER TABLE cards ADD COLUMN #{name} #{type}")

    execute("CREATE INDEX IF NOT EXISTS cards_by_package ON cards (work_package)")

    execute(
      "CREATE TABLE IF NOT EXISTS packages (package_id TEXT PRIMARY KEY, issue_ref TEXT NOT NULL, " <>
        "title TEXT NOT NULL, rank INTEGER, pinned INTEGER NOT NULL DEFAULT 0, ranked_by TEXT, " <>
        "rationale TEXT, opened_by TEXT, opened_at INTEGER, version INTEGER NOT NULL)"
    )

    execute("CREATE UNIQUE INDEX IF NOT EXISTS packages_by_ref ON packages (issue_ref)")
  end

  def down do
    execute("DROP TABLE IF EXISTS packages")
    execute("DROP INDEX IF EXISTS cards_by_package")
    for {name, _type} <- @card_columns, do: execute("ALTER TABLE cards DROP COLUMN #{name}")
  end

  defp columns(table) do
    %{rows: rows} = repo().query!("SELECT name FROM pragma_table_info('#{table}')", [], log: false)
    List.flatten(rows)
  end
end
