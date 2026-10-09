defmodule GuideCardLifecycle.MixProject do
  use Mix.Project

  def project do
    [
      app: :guide_card_lifecycle,
      version: "0.3.1",
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
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      # Commands dispatch through evoq; status is evoq_bit_flags. reckon_gater
      # validates the stream ids the desks mint.
      {:evoq, "~> 1.26"},
      {:reckon_gater, "~> 3.11"},
      # The responders implement macula_response and read the wire with
      # mcl_om_wire.
      {:mcl_om, "~> 0.39"},
      {:macula, "~> 14.2"}
    ]
  end
end
