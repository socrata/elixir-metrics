defmodule ElixirMetrics.TimerReporter do
  use ElixirMetrics.Reporter, label: :timer, kind: Telemetry.Metrics.Summary

  def init_metric(), do: []

  def accumulate(new_value, existing), do: [new_value | existing]

  def report(value) do
    %{
      "90" => Statistics.percentile(value, 90),
      "95" => Statistics.percentile(value, 95),
      "99" => Statistics.percentile(value, 99),
      "mean" => Statistics.mean(value),
      "max" => Enum.max(value, fn -> 0 end),
      "min" => Enum.min(value, fn -> 0 end)
    }
  end
end
