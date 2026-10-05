defmodule ProjectBoards.MixProject do
  use Mix.Project

  def project do
    [
      app: :project_boards,
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
      mod: {ProjectBoards.Application, []}
    ]
  end

  defp deps do
    [
      {:evoq, "~> 1.26"},
      {:esqlite, "~> 0.9"},
      # Not the web framework, only the pubsub library: each projection
      # announces its write, and the LiveViews react.
      {:phoenix_pubsub, "~> 2.3"},
      # The status flags and their names are the CMD department's own.
      {:guide_card_lifecycle, in_umbrella: true}
    ]
  end
end
