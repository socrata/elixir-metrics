defmodule ElixirMetrics.Reporter do
  defmacro __using__([label: label, kind: kind]) do
    quote do
      use GenServer
      require Logger

      def start_link(installed), do: GenServer.start_link(__MODULE__, installed, name: __MODULE__)

      def init([installed]) do
        Process.flag(:trap_exit, true)

        subscriptions = installed
          |> Enum.filter(fn %unquote(kind){} -> true; _ -> false end)
          |> Enum.map(fn %unquote(kind){event_name: event_name, measurement: measurement} = m ->
            qualified = event_name ++ [measurement]
            id = {__MODULE__, qualified, self()}
            Logger.info("Attached #{inspect id}")
            :telemetry.attach(id, qualified, &handle_event/4, m)
            qualified
          end)

        {:ok, {subscriptions, %{}}}
      end

      def handle_event(event_name, %{unquote(label) => metric}, _metadata, %unquote(kind){}) do
        GenServer.cast(__MODULE__, {:metric, event_name, metric})
      end

      def handle_cast({:metric, event_name, metric}, {subscriptions, accumulations}) do
        old_value = Map.get(accumulations, event_name, init_metric())
        new_value = accumulate(metric, old_value)
        {:noreply, {subscriptions, Map.put(accumulations, event_name, new_value)}}
      end

      def handle_call(:get_report, _, {subscriptions, accumulations}) do
        report = Enum.map(accumulations, fn {event_name, value} -> {event_name, report(value)} end)
        {:reply, report, {subscriptions, %{}}}
      end

      def terminate(_, {subscriptions, _}) do
        Enum.each(subscriptions, &(:telemetry.detach({__MODULE__, &1, self()})))
        :ok
      end

      def get_report(), do: GenServer.call(__MODULE__, :get_report)
    end
  end
end
