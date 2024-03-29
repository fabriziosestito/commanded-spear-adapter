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

  @impl GenServer
  def handle_info({_ref, Streams.read_resp(content: {:caught_up, _})}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({_ref, Streams.read_resp(content: {:fell_behind, _})}, state) do
    {:noreply, state}
  end

  def handle_info({_ref, Streams.read_resp() = read_resp}, state) do
    :ok =
      read_resp
      |> Spear.Event.from_read_response(json_decoder: fn data, _ -> data end)
      |> maybe_process_push(state)

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

  # Below clauses are a workaround to skip events on a system stream.
  # Using a filter would be better, but for some reason the filter causes no events to be received.
  defp maybe_process_push(%Spear.Event{metadata: %{stream_name: "$" <> _}} = event, _state) do
    Logger.debug("Skipping event #{inspect(event)}")
    :ok
  end

  defp maybe_process_push(
         %Spear.Event{
           link: %Spear.Event{metadata: %{stream_name: "$" <> _ = listening_stream}}
         } = event,
         %State{stream_name: listening_stream} = state
       ) do
    # if the event is a link on system stream, only process it when it's the stream we are listing on
    # this is the case for the 'all' stream when using a prefix
    process_push(event, state)
  end

  defp maybe_process_push(
         %Spear.Event{
           link: %Spear.Event{metadata: %{stream_name: "$" <> _}}
         } = event,
         _state
       ) do
    # if the link is on a system stream and it's not the stream we are listening on; ignore it
    Logger.debug("Skipping link event #{inspect(event)}")
    :ok
  end

  defp maybe_process_push(%Spear.Event{} = event, %State{} = state) do
    # in all other cases, process the event
    process_push(event, state)
  end

  defp process_push(%Spear.Event{} = event, %State{
         serializer: serializer,
         stream_prefix: stream_prefix,
         pubsub: pubsub
       }) do
    event
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
