defmodule ElixirMetrics.CounterReporter do
  use ElixirMetrics.Reporter, label: :count, kind: Telemetry.Metrics.Counter

  def init_metric(), do: 0

  def accumulate(change, existing), do: change + existing

  def report(value), do: value
end
