defmodule MclKanbanWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :mcl_kanban_web,
      version: "0.2.5",
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
      mod: {MclKanbanWeb.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.2"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_pubsub, "~> 2.3"},
      {:bandit, "~> 1.12"},
      {:jason, "~> 1.4"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:lazy_html, ">= 0.1.0", only: :test},
      # The UI acts through the same desks and queries the mesh uses; the
      # service app is a dep so the store is open before the Endpoint starts.
      {:guide_card_lifecycle, in_umbrella: true},
      {:project_boards, in_umbrella: true},
      {:query_boards, in_umbrella: true},
      {:mcl_kanban, in_umbrella: true}
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
