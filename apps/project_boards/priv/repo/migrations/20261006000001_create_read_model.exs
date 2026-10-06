defmodule ProjectBoards.Repo.Migrations.CreateReadModel do
  # The read model as v0.1.0 created it from code. IF NOT EXISTS, so a file
  # that v0.1.0 or v0.2.0 wrote (before the read model had migrations) adopts
  # this migration and keeps its rows.
  use Ecto.Migration

  def up do
    execute("CREATE TABLE IF NOT EXISTS boards ( board_id TEXT PRIMARY KEY, repo TEXT NOT NULL, status INTEGER NOT NULL, opened_by TEXT, opened_at INTEGER, archived_at INTEGER)")
    execute("CREATE TABLE IF NOT EXISTS cards ( card_id TEXT PRIMARY KEY, issue_ref TEXT NOT NULL, repo TEXT NOT NULL, board_id TEXT NOT NULL, title TEXT NOT NULL, story_role TEXT, story_ask TEXT, story_value TEXT, kind TEXT NOT NULL, rank INTEGER, rationale TEXT, ranked_by TEXT, lane TEXT, lane_node_id TEXT, holder TEXT, holder_node_id TEXT, status INTEGER NOT NULL, comment_count INTEGER NOT NULL DEFAULT 0, note TEXT, queued_by TEXT, queued_at INTEGER, claimed_at INTEGER, changed_at INTEGER, version INTEGER NOT NULL)")
    execute("CREATE INDEX IF NOT EXISTS cards_by_board ON cards (board_id)")
    execute("CREATE INDEX IF NOT EXISTS cards_by_holder ON cards (holder_node_id)")
    execute("CREATE TABLE IF NOT EXISTS card_tags ( card_id TEXT NOT NULL, tag TEXT NOT NULL, PRIMARY KEY (card_id, tag))")
    execute("CREATE TABLE IF NOT EXISTS card_links ( card_id TEXT NOT NULL, to_card_id TEXT NOT NULL, link TEXT NOT NULL, linked_by TEXT, linked_at INTEGER, PRIMARY KEY (card_id, to_card_id, link))")
    execute("CREATE INDEX IF NOT EXISTS card_links_to ON card_links (to_card_id)")
    execute("CREATE TABLE IF NOT EXISTS card_comments ( comment_id TEXT PRIMARY KEY, card_id TEXT NOT NULL, author TEXT NOT NULL, author_kind TEXT NOT NULL, text TEXT NOT NULL, at INTEGER NOT NULL)")
    execute("CREATE INDEX IF NOT EXISTS card_comments_by_card ON card_comments (card_id, at)")
    execute("CREATE TABLE IF NOT EXISTS crew ( node_id TEXT PRIMARY KEY, name TEXT NOT NULL, supervisor INTEGER NOT NULL DEFAULT 0, prioritiser INTEGER NOT NULL DEFAULT 0, roles TEXT NOT NULL, enlisted_at INTEGER)")
  end

  def down do
    for table <- ~w(crew card_comments card_links card_tags cards boards),
        do: execute("DROP TABLE IF EXISTS " <> table)
  end
end
