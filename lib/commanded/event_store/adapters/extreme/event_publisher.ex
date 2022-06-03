defmodule Commanded.EventStore.Adapters.Extreme.EventPublisher do
  @moduledoc false

  use GenServer

  require Logger

  defmodule State do
    @moduledoc false

    defstruct [:event_store, :pubsub, :subscription_ref, :stream_name, :serializer]
  end

  alias Commanded.EventStore.Adapters.Extreme.EventPublisher.State
  alias Commanded.EventStore.Adapters.Extreme.Mapper
  alias Commanded.EventStore.RecordedEvent

  def start_link({event_store, pubsub, stream_name, serializer}, opts \\ []) do
    state = %State{
      event_store: event_store,
      pubsub: pubsub,
      stream_name: stream_name,
      serializer: serializer
    }

    GenServer.start_link(__MODULE__, state, opts)
  end

  @impl GenServer
  def init(%State{} = state) do
    :ok = GenServer.cast(self(), :subscribe)

    {:ok, state}
  end

  @impl GenServer
  def handle_cast(:subscribe, state) do
    %State{event_store: event_store, stream_name: stream_name} = state

    {:ok, subscription} = Extreme.subscribe_to(event_store, self(), stream_name)

    ref = Process.monitor(subscription)

    {:noreply, %{state | subscription_ref: ref}}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %State{subscription_ref: ref} = state) do
    reconnect_delay = 1_000

    Logger.warn("Subscription to EventStore is down. Will retry in #{reconnect_delay} ms.")

    :timer.sleep(reconnect_delay)

    :ok = GenServer.cast(self(), :subscribe)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:on_event, push}, state) do
    :ok = process_push(push, state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  defp process_push(push, state) do
    %State{serializer: serializer, pubsub: pubsub} = state

    push
    |> Mapper.to_recorded_event(serializer)
    |> publish(pubsub)
  end

  defp publish(%RecordedEvent{} = recorded_event, pubsub) do
    :ok = publish_to_all(recorded_event, pubsub)
    :ok = publish_to_stream(recorded_event, pubsub)
  end

  defp publish_to_all(%RecordedEvent{} = recorded_event, pubsub) do
    Registry.dispatch(pubsub, "$all", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:events, [recorded_event]})
    end)
  end

  defp publish_to_stream(%RecordedEvent{} = recorded_event, pubsub) do
    %RecordedEvent{stream_id: stream_id} = recorded_event

    Registry.dispatch(pubsub, stream_id, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:events, [recorded_event]})
    end)
  end
end
