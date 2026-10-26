defmodule ProjectBoards.Repo.Migrations.AddCardApprovals do
  # The operators' signed approvals on cards (#30): one row per approval,
  # keyed by its card and nonce, with the encoded object kept as base64 text
  # so a reader re-verifies it without the event store.
  use Ecto.Migration

  def up do
    execute(
      "CREATE TABLE IF NOT EXISTS card_approvals ( card_id TEXT NOT NULL, nonce TEXT NOT NULL, " <>
        "kind TEXT NOT NULL, verdict INTEGER NOT NULL, operator_node_id TEXT NOT NULL, repo TEXT NOT NULL, " <>
        "ref TEXT, base TEXT, tip TEXT, tag TEXT, issue TEXT, signed_at INTEGER NOT NULL, " <>
        "recorded_by TEXT, recorded_at INTEGER NOT NULL, approval TEXT NOT NULL, " <>
        "PRIMARY KEY (card_id, nonce) )"
    )

    execute("CREATE INDEX IF NOT EXISTS card_approvals_by_card ON card_approvals (card_id, recorded_at)")
  end

  def down do
    execute("DROP TABLE IF EXISTS card_approvals")
  end
end
