defmodule MclKanban.MixProject do
  use Mix.Project

  def project do
    [
      app: :mcl_kanban,
      version: "0.8.0",
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
      # 1.4 was the macula-16 line; 1.6 is the macula-18 one (mcl-om#41), where
      # a handler-bearing capability must name who may call it and a
      # subscription must name who may deliver to it. The floor stays the minor
      # and not `~> 1.0`, which also admits 1.3.0, on macula `~> 15.6`
      # (macula-codebase-checks#14). The wire is 1.0 either way, which is what
      # keeps a service off a new wire unless it asks (mcl-om#27).
      {:mcl_om, "~> 1.6"},
      {:macula, "~> 18.0"},
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
