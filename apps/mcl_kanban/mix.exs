defmodule MclKanban.MixProject do
  use Mix.Project

  def project do
    [
      app: :mcl_kanban,
      version: "0.5.1",
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
      mod: {MclKanban.Application, []}
    ]
  end

  defp deps do
    [
      # 1.4 is the macula-16 line on wire 1.0 (macula-codebase-checks#4), the major
      # moving with the wire so no `~> 0.x` service floats onto a new wire by
      # itself (mcl-om#27). `~> 1.0` would also admit 1.3.0, which requires
      # macula `~> 15.6` (macula-codebase-checks#14).
      {:mcl_om, "~> 1.4"},
      {:macula, "~> 16.0"},
      # This service's own event store: mcl_om opens none (mcl-om#10).
      {:reckon_db, "~> 5.11"},
      {:evoq, "~> 1.26"},
      {:reckon_evoq, "~> 2.7"},
      # The departments start BEFORE this app, so their projections are
      # registered when the store subscription starts.
      {:guide_card_lifecycle, in_umbrella: true},
      {:project_boards, in_umbrella: true},
      {:query_boards, in_umbrella: true}
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
