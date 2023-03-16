defmodule Commanded.EventStore.Adapters.Spear.EventPublisher do
  @moduledoc false

  use GenServer

  require Logger
  require Spear.Records.Streams, as: Streams

  alias __MODULE__, as: State

  alias Commanded.EventStore.Adapters.Spear.Mapper
  alias Commanded.EventStore.RecordedEvent

  @reconnect_delay 1_000

  defstruct [:conn, :pubsub, :subscription, :stream_name, :serializer, :stream_prefix]

  def start_link({conn, pubsub, stream_name, serializer, stream_prefix}, opts \\ []) do
    state = %State{
      conn: conn,
      pubsub: pubsub,
      stream_name: stream_name,
      serializer: serializer,
      stream_prefix: stream_prefix
    }

    GenServer.start_link(__MODULE__, state, opts)
  end

  @impl GenServer
  def init(%State{} = state) do
    {:ok, state, {:continue, :subscribe}}
  end

  @impl GenServer
  def handle_continue(:subscribe, %State{conn: conn, stream_name: stream_name} = state) do
    filter =
      if stream_name == :all do
        Spear.Filter.exclude_system_events()
      end

    case Spear.subscribe(conn, self(), stream_name, raw?: true, filter: filter) do
      {:ok, subscription} ->
        {:noreply, %State{state | subscription: subscription}}

      {:error, reason} ->
        Logger.warn(
          "Cannot subscribe to #{stream_name} (reason: #{reason}). Will retry in #{@reconnect_delay} ms."
        )

        Process.send_after(self(), :retry, @reconnect_delay)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({_ref, Streams.read_resp(content: {:checkpoint, _})}, state) do
    {:noreply, state}
  end

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

    Process.send_after(self(), :retry, @reconnect_delay)

    {:noreply, state}
  end

  def handle_info(:retry, state) do
    {:noreply, state, {:continue, :subscribe}}
  end

  # This is a workaround to skip system events.
  # Using a filter would be better, but for some reason the filter causes no events to be received.
  defp process_push(%Spear.Event{type: "$>"}, _) do
    :ok
  end

  # Same workaround as above, but for links.
  defp process_push(%Spear.Event{link: %Spear.Event{type: "$>"}}, _) do
    :ok
  end

  defp process_push(push, %State{
         serializer: serializer,
         stream_prefix: stream_prefix,
         pubsub: pubsub
       }) do
    push
    |> Mapper.to_recorded_event(serializer, stream_prefix)
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
