defmodule ElixirMetrics.Poller do
  defmacro __using__(_) do
    quote do
      use GenServer
      import ElixirMetrics
      require Logger

      @interval Application.compile_env(:elixir_metrics, :collection_interval)
      def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)
      def init(_) do
        schedule_next_gather()
        {:ok, :nostate}
      end

      defp schedule_next_gather() do
        :erlang.send_after(@interval, self(), :gather)
      end

      def handle_info(:gather, state) do
        schedule_next_gather()
        poll()
        {:noreply, state}
      end
    end
  end
end
