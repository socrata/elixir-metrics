defmodule ElixirMetrics do
  use Supervisor
  require Logger
  alias ElixirMetrics.{
    CounterReporter,
    GaugeReporter,
    TimerReporter,
    Collectd,
  }

  @app_name Application.get_env(:elixir_metrics, :app_name)
  @use_collectd Application.get_env(:elixir_metrics, :use_collectd, true)

  def start_link(children) do
    Supervisor.start_link(__MODULE__, children, [name: __MODULE__])
  end

  def init(children) do
    installed = get_installed_metrics()
    maybe_collectd = if @use_collectd, do: [{Collectd, []}], else: []
    children = children ++ [
      {CounterReporter, [installed]},
      {GaugeReporter, [installed]},
      {TimerReporter, [installed]},
    ] ++ maybe_collectd

    Supervisor.init(
      children,
      strategy: :one_for_one,
      max_restarts: 1_000_000 # don't let metrics take down the app
    )
  end

  def update_timer!(key, millis), do: :telemetry.execute(key, %{timer: millis})

  def update_counter!(key, val), do: :telemetry.execute(key, %{count: val})

  def update_gauge!(key, val), do: :telemetry.execute(key, %{gauge: val})

  def gen_path(module, {func, _func_metadata}) do
    module = module
    |> Atom.to_string
    |> String.split(".")
    |> Enum.drop(2)
    |> Enum.map(fn s -> String.to_atom(s) end)

    [@app_name | module] ++ [func]
  end

  defp metrics_dir() do
    Application.app_dir(@app_name, "priv") |> Path.join("metrics")
  end

  def get_installed_metrics() do
    dir = metrics_dir()
    dir
    |> File.ls!
    |> Enum.filter(fn name -> String.ends_with?(name, ".metric") end)
    |> Enum.map(fn f ->
      Path.join(dir, f) |> File.read! |> :erlang.binary_to_term
    end)
  end

  def install_metric(kind, path) do
    metrics_dir() |> File.mkdir_p!

    qualified = path ++ [kind]
    p = Enum.map(qualified, &to_string/1) |> Enum.join(".")
    metric = case kind do
      :counter -> Telemetry.Metrics.counter(p)
      :timer -> Telemetry.Metrics.summary(p)
      :gauge -> Telemetry.Metrics.last_value(p)
    end
    file = Path.join([metrics_dir(), "#{p}.metric"])
    # If you want to see which metrics are being added to the system,
    # uncomment this next line. Since metrics are added at compile time,
    # you just need to run `mix compile` to get them all printed out.
    # IO.puts "Installed metric: #{metric.__struct__} #{p}.metric"
    contents = :erlang.term_to_binary(metric)
    File.write!(file, contents)

    qualified
  end

  def do_count(path, amount) do
    qualified = install_metric(:counter, path)

    quote do
      ElixirMetrics.update_counter!(unquote(qualified), unquote(amount))
    end
  end

  defmacro count() do
    path = gen_path(__CALLER__.module, __CALLER__.function)
    do_count(path, 1)
  end

  defmacro count(path), do: do_count(path, 1)
  defmacro count(path, value), do: do_count(path, value)

  defmacro defq({fun_name, fun_meta, _fun_args} = args, expr) do
    [@app_name | rest] = gen_path(__CALLER__.module, {fun_name, fun_meta})
    path = [@app_name, :defq | rest]
    qualified = install_metric(:counter, path)

    quote do
      def unquote(args) do
        ElixirMetrics.update_counter!(unquote(qualified), 1)
        unquote(expr[:do])
      end
    end
  end

  def do_gauge(path, value) do
    qualified = install_metric(:gauge, path)

    quote do
      ElixirMetrics.update_gauge!(unquote(qualified), unquote(value))
    end
  end

  defmacro set_gauge(value) do
    path = gen_path(__CALLER__.module, __CALLER__.function)
    do_gauge(path, value)
  end

  defmacro set_gauge(path, value) do
    do_gauge(path, value)
  end

  defp do_timed(path, body) do
    qualified = install_metric(:timer, path)

    quote do
      start = System.os_time()
      res = unquote(body[:do])
      elapsed = System.os_time() - start
      millis = System.convert_time_unit(elapsed, :native, :millisecond)
      ElixirMetrics.update_timer!(unquote(qualified), millis)
      res
    end
  end

  defmacro timed(body), do: do_timed(gen_path(__CALLER__.module, __CALLER__.function), body)
  defmacro timed(path, [do: _] = body), do: do_timed(path, body)
  defmacro timed(path, value_ms) do
    qualified = install_metric(:timer, path)

    quote do
      millis = System.convert_time_unit(unquote(value_ms), :native, :millisecond)
      ElixirMetrics.update_timer!(unquote(qualified), millis)
    end
  end

  defmacro log_timed(msg, body) do
    quote do
      start = System.os_time()
      res = unquote(body[:do])
      elapsed = System.os_time() - start
      millis = System.convert_time_unit(elapsed, :native, :millisecond)
      Logger.info("#{unquote(msg)} (in #{millis} ms)")
      res
    end
  end

  defmacro get_timed(body) do
    quote do
      start = System.os_time()
      res = unquote(body[:do])
      elapsed = System.os_time() - start
      micros = System.convert_time_unit(elapsed, :native, :microsecond)
      {micros, res}
    end
  end

  def top(n \\ 10) do
    :erlang.processes
    |> Enum.flat_map(fn p ->
      case :erlang.process_info(p, :memory) do
        {:memory, m} -> [{p, m}]
        _ -> []
      end
    end)
    |> Enum.sort_by(fn {_, m} -> m * -1 end)
    |> Enum.take(n)
    |> Enum.map(fn {p, m} -> {p, :erlang.process_info(p), m / 1_000_000} end)
  end
end
