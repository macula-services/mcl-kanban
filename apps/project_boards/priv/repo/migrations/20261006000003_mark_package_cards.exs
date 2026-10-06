defmodule ProjectBoards.Repo.Migrations.MarkPackageCards do
  # A package's own card (filed into its own package) heads the package
  # (#15): it is never claimed, never a member and never counted as waiting
  # work. package_card is 1 for it, written by the filing projections; cards
  # filed before this release are marked here.
  use Ecto.Migration

  def up do
    execute("ALTER TABLE cards ADD COLUMN package_card INTEGER NOT NULL DEFAULT 0")

    execute(
      "UPDATE cards SET package_card = 1 WHERE work_package IS NOT NULL AND work_package = issue_ref"
    )
  end

  def down, do: execute("ALTER TABLE cards DROP COLUMN package_card")
end
