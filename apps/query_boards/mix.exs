defmodule QueryBoards.MixProject do
  use Mix.Project

  def project do
    [
      app: :query_boards,
      version: "0.1.0",
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
      mod: {QueryBoards.Application, []}
    ]
  end

  defp deps do
    [
      {:esqlite, "~> 0.9"},
      # The read model file and its schema belong to project_boards.
      {:project_boards, in_umbrella: true},
      {:guide_card_lifecycle, in_umbrella: true},
      {:mcl_om, "~> 0.37"},
      {:macula, "~> 13.5"}
    ]
  end
end
