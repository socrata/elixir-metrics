defmodule ElixirMetrics.GaugeReporter do
  use ElixirMetrics.Reporter, label: :gauge, kind: Telemetry.Metrics.LastValue

  def init_metric(), do: nil

  def accumulate(new_value, _existing), do: new_value

  def report(value), do: value
end
