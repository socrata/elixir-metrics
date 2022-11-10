defmodule ElixirMetrics.Collectd do
  require Logger
  use GenServer
  alias ElixirMetrics.{CounterReporter, GaugeReporter, TimerReporter}

  @app_name Application.get_env(:elixir_metrics, :app_name)
  @read_timeout 15_000
  @buffer_max 200
  @socket_path :erlang.binary_to_list(Application.get_env(:elixir_metrics, :unixsock))
  @interval Application.get_env(:elixir_metrics, :collection_interval)
  @connect_timeout Application.get_env(:elixir_metrics, :connect_timeout)
  @reconnect_interval Application.get_env(:elixir_metrics, :reconnect_interval)

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init([]) do
    schedule_next_gather()
    socket = nil
    buffer = []
    state = {socket, buffer}
    maybe_reconnect(state, 0)
    {:ok, state}
  end

  defp schedule_next_gather() do
    :erlang.send_after(@interval, self(), :gather)
  end

  def get_reports() do
    [
      counter: CounterReporter,
      gauge: GaugeReporter,
      timer: TimerReporter
    ]
    |> Enum.map(fn {k, v} ->
      {k, v.get_report()}
    end)
  end


  defp maybe_reconnect({nil, _}, interval) do
    Logger.info("Attempting collectd reconnect in #{interval}ms")
    :erlang.send_after(interval, self(), :reconnect)
  end
  defp maybe_reconnect(_, _), do: :ok
  defp maybe_reconnect(state), do: maybe_reconnect(state, @reconnect_interval)

  defp send_buffer({nil, _} = state), do: state
  defp send_buffer({_, []}  = state), do: state
  defp send_buffer({socket, [{name, value} | rest] = buffer} = _state) do
    case put_value(name, value, socket) do
      {:ok, socket} ->
        send_buffer({socket, rest})
      {:error, socket} ->
        {socket, buffer}
    end
  end

  def handle_info(:reconnect, {nil, buffer}) do
    IO.puts("Connect to #{@socket_path}")
    case :gen_tcp.connect({:local, @socket_path}, 0, [:local, active: false, mode: :binary], @connect_timeout) do
      {:ok, socket} ->
        {:noreply, {socket, buffer}}
      _ ->
        new_state = {nil, buffer}
        maybe_reconnect(new_state)
        {:noreply, new_state}
    end
  end
  def handle_info(:reconnect, state), do: {:noreply, state}

  def handle_info(:gather, nil) do
    schedule_next_gather()
    Logger.warn("Attempted to gather metrics, but could not connect to collectd!")
    {:noreply, nil}
  end
  def handle_info(:gather, state) do
    schedule_next_gather()
    state =
      get_reports()
      |> Enum.reduce(state, fn {_kind, values}, state ->
        Enum.reduce(values, state, fn {key, value}, state ->
          send_metric(key, value, state)
        end)
      end)
      |> send_buffer

    maybe_reconnect(state)

    {:noreply, state}
  end

  defp send_metric(name, values, state) when is_map(values) do
    Enum.reduce(values, state, fn {stat_name, stat_value}, state ->
      send_metric(name ++ [stat_name], stat_value, state)
    end)
  end
  defp send_metric(name, value, {socket, buffer}) do
    case put_value(name, value, socket) do
      {:error, socket} -> buffer_value(name, value, {socket, buffer})
      {:ok, socket} -> {socket, buffer}
    end
  end

  defp buffer_value(name, value, {socket, buffer}), do: {socket, Enum.take([{name, value} | buffer], @buffer_max)}

  defp put_value(_name, _value, nil), do: {:error, nil}
  defp put_value(name, value, socket) do
    name = Enum.join(name, "_")
    host = :net_adm.localhost()
    request = "PUTVAL #{host}/docker-#{to_string(@app_name)}/gauge-#{name} N:#{value}\n" |> to_charlist
    case :gen_tcp.send(socket, request) do
      :ok ->
        case :gen_tcp.recv(socket, 0, @read_timeout) do
          {:ok, "0" <> _} ->
            {:ok, socket}
          {:ok, "-1 " <> reason} ->
            Logger.warn("Error reply when sending metrics to collectd! #{reason} Dropping #{inspect {name, value}}")
            {:ok, socket}
          err ->
            Logger.error("Error sending metrics to collectd! #{inspect err}")
            {:error, nil}
        end
      {:error, _} ->
        {:error, nil}
    end
  end
end
