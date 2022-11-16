# ElixirMetrics

## Usage

```
config :elixir_metrics,
  app_name: :dsmapi,
  unixsock: "/var/run/collectd-unixsock",
  connect_timeout: 5_000,
  reconnect_interval: 5_000,
  collection_interval: 60_000,
  use_collectd: true
```

in your application tree
```
supervisor(ElixirMetrics, [metrics_children]),
```

Where metrics_children is any polling processes you want to install. It can be `[]` and you can
just use the metrics library normally, doing things like `Metrics.count([:my_app, :some_event])`. But you can write additional poller processes by doing something like:

```
defmodule MyApp.CoolPoller do
  use ElixirMetrics.Poller
  def poll() do
    set_gauge([:my, :florp, :metric, :path], Florps.current_florp_count())
  end
end
```
and then pass it to the metric supervisor
```
metrics_children = [
  {MyApp.CoolPoller, []}
]
```
and your poll function will get run on the collection interval.


## Installation


If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `elixir_metrics` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:elixir_metrics, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/elixir_metrics](https://hexdocs.pm/elixir_metrics).

