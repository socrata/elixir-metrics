defmodule ElixirMetrics.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_metrics,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry_metrics, "~> 0.3"},
      {:telemetry, "~> 1.0"},
      {:telemetry_poller, "~> 0.4"},
      {:statistics, "~> 0.6.1"}
    ]
  end
end
