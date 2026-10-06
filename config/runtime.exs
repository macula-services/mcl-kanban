import Config

# Evaluated on every boot: dev, test and the release. Defaults are dev-safe (a
# writable local path, the io.macula realm, no mesh); the deployed container
# sets the real values. Fleet placement lives in macula-io/macula-fleet.
#
# A TEST run gets a fresh data dir every time: the reckon store leaves dets
# files behind, and a second run against the same dir fails to reopen them.
data_dir =
  if config_env() == :test do
    Path.join(System.tmp_dir!(), "mcl_kanban_test_#{System.unique_integer([:positive])}")
  else
    System.get_env("MCL_DATA_DIR", "/tmp/mcl-kanban-dev")
  end

System.put_env("MCL_DATA_DIR", data_dir)

health_port = String.to_integer(System.get_env("MCL_HEALTH_PORT", "8492"))

# THE REALM NAME IS THE ONE INPUT; THE TAG IS DERIVED FROM IT HERE, so the two
# can never disagree.
realm_name = System.get_env("MCL_REALM_NAME", "io.macula")
realm = :crypto.hash(:sha256, realm_name) |> Base.encode16(case: :lower)

config :mcl_om,
  # Charlists: the dets/ra layer under reckon-db rejects a binary path.
  identity_key_path:
    String.to_charlist(
      System.get_env("MCL_IDENTITY_KEY_PATH", Path.join([data_dir, "identity", "identity.key"]))
    ),
  health_port: health_port,
  capability_topic: "_mesh.cap.",
  # The wire namespace: every procedure is mcl-kanban/<name>.
  org: "mcl-kanban",
  realm: realm,
  # The realm's public signing key, hex. Unset in a local dev or test boot,
  # which then runs with no mesh pool.
  realm_key: System.get_env("MCL_REALM_KEY", "")

# THE READ MODEL: one sqlite file beside the store. WAL lets the queries read
# while a projection writes; IMMEDIATE transactions take the write lock up
# front, so two projections queue on the busy timeout instead of failing.
config :project_boards, ProjectBoards.Repo,
  database: Path.join(data_dir, "kanban.sqlite3"),
  journal_mode: :wal,
  busy_timeout: 5_000,
  default_transaction_mode: :immediate,
  pool_size: 5

# THE PQ CRYPTO PROFILE, without which this node does not peer.
config :macula, crypto_profile: :pq_hybrid

# MANDATORY: MclKanban.EventStore starts the per-store evoq subscription,
# which crashes on {not_configured, event_store_adapter} without this block.
# The store id here and MclKanban.Service.event_store/0's id must agree; a
# test compares them.
config :evoq,
  event_store_adapter: :reckon_evoq_adapter,
  subscription_adapter: :reckon_evoq_adapter,
  snapshot_store_adapter: :reckon_evoq_adapter,
  store_id: :mcl_kanban_store

# THE OWNER'S UI. It acts as the owner, so it listens on loopback by default
# and Raf reaches it through his own tunnel. A container publishes it with
# MCL_HTTP_IP=0.0.0.0 inside and a 127.0.0.1-only port on the host.
http_ip =
  System.get_env("MCL_HTTP_IP", "127.0.0.1")
  |> String.to_charlist()
  |> :inet.parse_address()
  |> then(fn {:ok, ip} -> ip end)

http_port = String.to_integer(System.get_env("MCL_HTTP_PORT", "4010"))

# Signs the LiveView socket. A release REQUIRES it; dev and test get a fixed
# value that protects nothing.
secret_key_base =
  if config_env() == :prod do
    System.fetch_env!("SECRET_KEY_BASE")
  else
    System.get_env(
      "SECRET_KEY_BASE",
      "mkbdev00000000000000000000000000000000000000000000000000000000000000000000000"
    )
  end

config :mcl_kanban_web, MclKanbanWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: MclKanbanWeb.PubSub,
  http: [ip: http_ip, port: http_port],
  server: config_env() != :test,
  secret_key_base: secret_key_base,
  live_view: [signing_salt: "mkb_live_view_salt"],
  # The socket is the owner's only action path, so it answers only the local
  # origins a tunnel (`ssh -L 4010:127.0.0.1:4010 box`) produces. Without
  # this, a page on any name the attacker rebinds to 127.0.0.1 would drive
  # the UI as the owner. MCL_HTTP_ORIGINS adds origins (comma separated, as
  # //host:port) for a tunnel on another local port. Reaching the UI under
  # Raf's own identity from elsewhere is part 2.
  check_origin:
    Enum.map(["localhost", "127.0.0.1", "[::1]"], &"//#{&1}:#{http_port}") ++
      (System.get_env("MCL_HTTP_ORIGINS", "")
       |> String.split(",", trim: true)
       |> Enum.map(&String.trim/1))
