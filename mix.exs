defmodule MclKanbanUmbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.2.1",
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      releases: releases(),
      dialyzer: dialyzer()
    ]
  end

  defp releases do
    [
      mcl_kanban: [
        # Every app in the umbrella is listed: `mix release` does not include
        # an umbrella app just because it sits under apps/, and a missing one
        # is silently left out of the image. Boot order: the departments, then
        # the service (which opens the store and boots mcl_om), then the web UI.
        applications: [
          guide_card_lifecycle: :permanent,
          project_boards: :permanent,
          query_boards: :permanent,
          mcl_kanban: :permanent,
          mcl_kanban_web: :permanent
        ]
      ]
    ]
  end

  # Declared once at the umbrella root: every apps/*/mix.exs points
  # deps_path/build_path at ../../, so `mix credo` and `mix dialyzer` from the
  # root cover every app.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      # macula and reckon_db ship beams without debug_info (NIF-heavy rebar3
      # packages), so the PLT cannot scan them.
      plt_ignore_apps: [:macula, :reckon_db],
      plt_core_path: "priv/plts/core",
      plt_local_path: "priv/plts/local",
      ignore_warnings: ".dialyzer_ignore.exs",
      flags: [:unmatched_returns, :error_handling]
    ]
  end
end
