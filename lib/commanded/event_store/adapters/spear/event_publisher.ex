defmodule Commanded.EventStore.Adapters.Spear.EventPublisher do
  @moduledoc false

  use GenServer

  require Logger
  require Spear.Records.Streams, as: Streams

  alias __MODULE__, as: State

  alias Commanded.EventStore.Adapters.Spear.Mapper
  alias Commanded.EventStore.RecordedEvent

  @reconnect_delay 1_000

  defstruct [:conn, :pubsub, :subscription, :stream_name, :serializer]

  def start_link({conn, pubsub, stream_name, serializer}, opts \\ []) do
    state = %State{
      conn: conn,
      pubsub: pubsub,
      stream_name: stream_name,
      serializer: serializer
    }

    GenServer.start_link(__MODULE__, state, opts)
  end

  @impl GenServer
  def init(%State{} = state) do
    GenServer.cast(self(), :subscribe)

    {:ok, state}
  end

  @impl GenServer
  def handle_cast(:subscribe, %State{conn: conn, stream_name: stream_name} = state) do
    {:ok, subscription} = Spear.subscribe(conn, self(), stream_name, raw?: true)

    {:noreply, %State{state | subscription: subscription}}
  end

  @impl GenServer
  def handle_info({_ref, Streams.read_resp() = read_resp}, state) do
    :ok =
      read_resp
      |> Spear.Event.from_read_response(json_decoder: fn data, _ -> data end)
      |> process_push(state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:eos, _, reason}, state) do
    Logger.warn(
      "Subscription to EventStore is down (reason: #{reason}). Will retry in #{@reconnect_delay} ms."
    )

    Process.sleep(@reconnect_delay)
    GenServer.cast(self(), :subscribe)

    {:noreply, state}
  end

  defp process_push(push, %State{serializer: serializer, pubsub: pubsub}) do
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
