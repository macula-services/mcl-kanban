defmodule MclKanban.MixProject do
  use Mix.Project

  def project do
    [
      app: :mcl_kanban,
      version: "0.2.1",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:mcl_om, "~> 0.37"},
      {:macula, "~> 13.5"},
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
end
