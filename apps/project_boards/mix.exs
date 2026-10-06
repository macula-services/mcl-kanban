defmodule ProjectBoards.MixProject do
  use Mix.Project

  def project do
    [
      app: :project_boards,
      version: "0.2.1",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {ProjectBoards.Application, []}
    ]
  end

  defp deps do
    [
      {:evoq, "~> 1.26"},
      # The read model is one sqlite file with its schema in migrations
      # (priv/repo/migrations), run before the app boots (bin/start).
      {:ecto_sql, "~> 3.14"},
      {:ecto_sqlite3, "~> 0.25"},
      # Not the web framework, only the pubsub library: each projection
      # announces its write, and the LiveViews react.
      {:phoenix_pubsub, "~> 2.3"},
      # The status flags and their names are the CMD department's own.
      {:guide_card_lifecycle, in_umbrella: true}
    ]
  end

  # The read model is migrated before the tests boot the apps, as bin/start
  # migrates before the release boots.
  defp aliases do
    [
      test: [
        "ecto.create -r ProjectBoards.Repo --quiet",
        "ecto.migrate -r ProjectBoards.Repo --quiet",
        "test"
      ]
    ]
  end
end
