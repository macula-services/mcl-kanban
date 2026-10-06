defmodule ProjectBoards.ReadModel do
  # The board read model: one sqlite file, one connection, owned by this
  # process (an esqlite connection belongs to the process that opened it).
  # The schema lives here and only here. Each projection's writes run in one
  # transaction. WAL lets the query department read while this writes.
  @moduledoc false

  use GenServer

  @schema [
    "PRAGMA journal_mode=WAL",
    """
    CREATE TABLE IF NOT EXISTS boards (
      board_id TEXT PRIMARY KEY, repo TEXT NOT NULL, status INTEGER NOT NULL,
      opened_by TEXT, opened_at INTEGER, archived_at INTEGER)
    """,
    """
    CREATE TABLE IF NOT EXISTS cards (
      card_id TEXT PRIMARY KEY, issue_ref TEXT NOT NULL, repo TEXT NOT NULL,
      board_id TEXT NOT NULL, title TEXT NOT NULL, story_role TEXT,
      story_ask TEXT, story_value TEXT, kind TEXT NOT NULL, rank INTEGER,
      rationale TEXT, ranked_by TEXT, lane TEXT, lane_node_id TEXT, holder TEXT,
      holder_node_id TEXT, status INTEGER NOT NULL, comment_count INTEGER NOT NULL DEFAULT 0,
      note TEXT, queued_by TEXT, queued_at INTEGER, claimed_at INTEGER,
      changed_at INTEGER, version INTEGER NOT NULL, ranked_at INTEGER,
      work_package TEXT, package_rank INTEGER)
    """,
    "CREATE INDEX IF NOT EXISTS cards_by_package ON cards (work_package)",
    "CREATE INDEX IF NOT EXISTS cards_by_board ON cards (board_id)",
    "CREATE INDEX IF NOT EXISTS cards_by_holder ON cards (holder_node_id)",
    """
    CREATE TABLE IF NOT EXISTS card_tags (
      card_id TEXT NOT NULL, tag TEXT NOT NULL, PRIMARY KEY (card_id, tag))
    """,
    """
    CREATE TABLE IF NOT EXISTS card_links (
      card_id TEXT NOT NULL, to_card_id TEXT NOT NULL, link TEXT NOT NULL,
      linked_by TEXT, linked_at INTEGER, PRIMARY KEY (card_id, to_card_id, link))
    """,
    "CREATE INDEX IF NOT EXISTS card_links_to ON card_links (to_card_id)",
    """
    CREATE TABLE IF NOT EXISTS card_comments (
      comment_id TEXT PRIMARY KEY, card_id TEXT NOT NULL, author TEXT NOT NULL,
      author_kind TEXT NOT NULL, text TEXT NOT NULL, at INTEGER NOT NULL)
    """,
    "CREATE INDEX IF NOT EXISTS card_comments_by_card ON card_comments (card_id, at)",
    """
    CREATE TABLE IF NOT EXISTS packages (
      package_id TEXT PRIMARY KEY, issue_ref TEXT NOT NULL, title TEXT NOT NULL,
      rank INTEGER, pinned INTEGER NOT NULL DEFAULT 0, ranked_by TEXT, rationale TEXT,
      opened_by TEXT, opened_at INTEGER, version INTEGER NOT NULL)
    """,
    "CREATE UNIQUE INDEX IF NOT EXISTS packages_by_ref ON packages (issue_ref)",
    """
    CREATE TABLE IF NOT EXISTS crew (
      node_id TEXT PRIMARY KEY, name TEXT NOT NULL, supervisor INTEGER NOT NULL DEFAULT 0,
      prioritiser INTEGER NOT NULL DEFAULT 0, roles TEXT NOT NULL, enlisted_at INTEGER)
    """
  ]

  def start_link(path), do: GenServer.start_link(__MODULE__, path, name: __MODULE__)

  @doc "The sqlite file, under MCL_DATA_DIR."
  def path, do: Path.join(System.get_env("MCL_DATA_DIR", "/tmp/mcl-kanban-dev"), "kanban.sqlite3")

  @doc "Runs the statements in one transaction."
  def write(statements), do: GenServer.call(__MODULE__, {:write, statements}, 10_000)

  def q(sql, args), do: GenServer.call(__MODULE__, {:q, sql, args}, 10_000)

  @impl true
  def init(path) do
    :ok = File.mkdir_p(Path.dirname(path))
    {:ok, conn} = :esqlite3.open(String.to_charlist(path))
    :ok = Enum.each(@schema, &(:ok = exec(conn, &1)))
    {:ok, %{conn: conn}}
  end

  @impl true
  def handle_call({:write, statements}, _from, %{conn: conn} = state) do
    {:reply, transaction(conn, statements), state}
  end

  def handle_call({:q, sql, args}, _from, %{conn: conn} = state),
    do: {:reply, :esqlite3.q(conn, sql, args), state}

  def handle_call(:ping, _from, state), do: {:reply, :ok, state}

  defp transaction(conn, statements) do
    :ok = exec(conn, "BEGIN IMMEDIATE")
    committed(Enum.reduce_while(statements, :ok, &run(conn, &1, &2)), conn)
  end

  defp run(conn, {sql, args}, :ok), do: ran(:esqlite3.q(conn, sql, Enum.map(args, &bound/1)))

  # esqlite binds an atom as its name, so nil would land as the text "nil";
  # :undefined is how esqlite writes NULL.
  defp bound(nil), do: :undefined
  defp bound(value), do: value

  defp ran(rows) when is_list(rows), do: {:cont, :ok}
  defp ran({:error, _} = error), do: {:halt, error}

  defp committed(:ok, conn), do: exec(conn, "COMMIT")

  defp committed(error, conn) do
    _ = exec(conn, "ROLLBACK")
    error
  end

  defp exec(conn, sql), do: :esqlite3.exec(conn, sql)
end
