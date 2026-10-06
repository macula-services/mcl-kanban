import Config

# Compile-time config only. Everything env-driven lives in config/runtime.exs,
# evaluated on every boot. This file holds what build tools need without a
# boot: the esbuild profiles the Containerfile runs.

config :logger, :console, format: "$date $time [$level] $message\n"

config :phoenix, :json_library, Jason

# The read model's Repo; its migrations run before boot (bin/start, and the
# test alias in each app that reads it).
config :project_boards, ecto_repos: [ProjectBoards.Repo]

# NODE_PATH=deps lets esbuild resolve `import "phoenix"` and
# `import "phoenix_live_view"` against the hex deps' own package.json; no npm.
config :esbuild,
  version: "0.25.0",
  mcl_kanban_web: [
    args: ~w(js/app.js --bundle --target=es2022 --outfile=../priv/static/assets/app.js),
    cd: Path.expand("../apps/mcl_kanban_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ],
  mcl_kanban_web_css: [
    args: ~w(css/app.css --bundle --loader:.woff2=file --outfile=../priv/static/assets/app.css),
    cd: Path.expand("../apps/mcl_kanban_web/assets", __DIR__)
  ]
