defmodule Commanded.EventStore.Adapters.Spear.Subscription do
  @moduledoc false

  use GenServer

  require Spear.Records.Persistent, as: Persistent
  require Logger

  alias __MODULE__, as: State

  alias Commanded.EventStore.Adapters.Spear.Mapper
  alias Commanded.EventStore.RecordedEvent

  defstruct [
    :conn,
    :last_seen_event_id,
    :last_seen_event_number,
    :name,
    :retry_interval,
    :serializer,
    :stream_prefix,
    :stream,
    :start_from,
    :concurrency_limit,
    :subscriber,
    :subscriber_ref,
    :subscription,
    subscribed?: false
  ]

  @doc """
  Start a process to create and connect a persistent connection to the Event Store
  """
  def start_link(
        event_store,
        conn,
        stream,
        subscription_name,
        subscriber,
        serializer,
        stream_prefix,
        opts
      ) do
    if Keyword.get(opts, :partition_by) do
      raise "commanded_spear_adapter does not support partition_by"
    end

    state = %State{
      conn: conn,
      stream: stream,
      name: subscription_name,
      serializer: serializer,
      stream_prefix: stream_prefix,
      subscriber: subscriber,
      start_from: Keyword.get(opts, :start_from),
      concurrency_limit: Keyword.get(opts, :concurrency_limit, 1),
      retry_interval: subscription_retry_interval()
    }

    # Prevent duplicate subscriptions by stream/name
    name = {event_store, __MODULE__, stream, subscription_name, Keyword.get(opts, :index, 1)}

    GenServer.start_link(__MODULE__, state, name: {:global, name})
  end

  @doc """
  Positively acknowledges the receipt of the given event.
  """
  def ack(subscription, event_number) do
    GenServer.call(subscription, {:ack, event_number})
  end

  @doc """
  Negatively acknowledges the receipt of the given event.
  """
  @spec nack(
          pid(),
          non_neg_integer(),
          [{:action, Spear.PersistentSubscription.nack_action()}]
        ) :: :ok
  def nack(subscription, event_number, opts \\ []) do
    GenServer.call(subscription, {:nack, event_number, opts})
  end

  @impl GenServer
  def init(%State{subscriber: subscriber} = state) do
    Process.flag(:trap_exit, true)
    send(self(), :subscribe)

    {:ok, %State{state | subscriber_ref: Process.monitor(subscriber)}}
  end

  @impl GenServer
  def handle_call(
        {:ack, event_number},
        _from,
        %State{
          conn: conn,
          last_seen_event_number: event_number,
          subscription: subscription,
          last_seen_event_id: event_id
        } = state
      ) do
    Logger.debug(fn ->
      describe(state) <> " ack event: #{inspect(event_number)} #{inspect(event_id)}"
    end)

    :ok = Spear.ack(conn, subscription, [event_id])

    {:reply, :ok, %State{state | last_seen_event_id: nil, last_seen_event_number: nil}}
  end

  @impl GenServer
  def handle_call(
        {:nack, event_number, opts},
        _from,
        %State{
          conn: conn,
          last_seen_event_number: event_number,
          subscription: subscription,
          last_seen_event_id: event_id
        } = state
      ) do
    Logger.debug(fn -> describe(state) <> " nack event: #{inspect(event_number)}" end)
    :ok = Spear.nack(conn, subscription, [event_id], opts)

    {:reply, :ok, %State{state | last_seen_event_id: nil, last_seen_event_number: nil}}
  end

  @impl GenServer
  def handle_info(:subscribe, state) do
    Logger.debug(fn ->
      describe(state) <>
        " to stream: #{inspect(state.stream)}, start from: #{inspect(state.start_from)}"
    end)

    {:noreply, subscribe(state)}
  end

  @impl GenServer
  def handle_info(
        {_, Persistent.read_resp() = read_resp},
        %State{stream: listening_stream} = state
      ) do
    case Mapper.to_spear_event(read_resp) do
      # Some events are not skipped even if the filter is set, this is a workaround for this issue.
      # For instance when a stream is deleted, the subscription receives a deleted system event.
      %Spear.Event{metadata: %{stream_name: "$" <> _}} = event ->
        skip_event(event, state)

      # Same workaround as above, but for links.
      %Spear.Event{
        link:
          %Spear.Event{
            metadata: %{stream_name: "$" <> _ = stream_name}
          } = link
      } = event ->
        # if the event is a link on system stream, only process it when it's the stream we are listing on
        # this is the case for the 'all' stream when using a prefix
        if stream_name == listening_stream do
          process_event(event, state)
        else
          skip_event(link, state)
        end

      event ->
        process_event(event, state)
    end
  end

  @impl GenServer
  def handle_info(
        {:DOWN, subscriber_ref, :process, _pid, reason},
        %State{subscriber_ref: subscriber_ref} = state
      ) do
    Logger.debug(fn -> describe(state) <> " down due to: #{inspect(reason)} (subscriber)" end)

    {:stop, {:shutdown, :subscriber_shutdown}, state}
  end

  @impl GenServer
  def handle_info(
        {:eos, subscription, reason},
        %State{subscription: subscription} = state
      ) do
    Logger.debug(fn -> describe(state) <> " down due to: #{inspect(reason)} (subscription)" end)

    {:stop, {:shutdown, :subscription_shutdown}, state}
  end

  @impl GenServer
  def terminate(_, state) do
    # Fixes commanded tests
    Process.sleep(1_000)

    state
  end

  defp skip_event(
         %Spear.Event{id: event_id} = event,
         %State{conn: conn, subscription: subscription} = state
       ) do
    Logger.debug(fn -> describe(state) <> " skipping event: #{inspect(event)}" end)
    :ok = Spear.ack(conn, subscription, [event_id])

    {:noreply, state}
  end

  defp process_event(
         %Spear.Event{} = event,
         %State{
           subscriber: subscriber,
           serializer: serializer,
           stream_prefix: stream_prefix
         } = state
       ) do
    Logger.debug(fn -> describe(state) <> " received event: #{inspect(event)}" end)

    %RecordedEvent{event_number: event_number} =
      recorded_event = Mapper.to_recorded_event(event, serializer, stream_prefix)

    send(subscriber, {:events, [recorded_event]})

    {:noreply,
     %State{
       state
       | last_seen_event_id: event_id_to_ack(event),
         last_seen_event_number: event_number
     }}
  end

  defp subscribe(%State{} = state) do
    with :ok <- create_persistent_subscription(state),
         {:ok, subscription} <- connect_to_persistent_subscription(state) do
      :ok = notify_subscribed(state)

      %State{
        state
        | subscription: subscription,
          subscribed?: true
      }
    else
      err ->
        %State{retry_interval: retry_interval} = state

        Logger.debug(fn ->
          describe(state) <>
            " failed to subscribe due to: #{inspect(err)}. Will retry in #{retry_interval}ms"
        end)

        Process.send_after(self(), :subscribe, retry_interval)

        %State{state | subscribed?: false}
    end
  end

  defp notify_subscribed(%State{subscriber: subscriber}) do
    send(subscriber, {:subscribed, self()})

    :ok
  end

  defp create_persistent_subscription(%State{} = state) do
    %State{
      conn: conn,
      name: name,
      stream: stream,
      start_from: start_from,
      concurrency_limit: concurrency_limit
    } = state

    settings = %Spear.PersistentSubscription.Settings{
      max_subscriber_count: concurrency_limit,
      message_timeout: 10_000,
      resolve_links?: true
    }

    case Spear.create_persistent_subscription(
           conn,
           stream,
           name,
           settings,
           from: normalize_start_from(start_from),
           filter: Spear.Filter.exclude_system_events()
         ) do
      :ok ->
        :ok

      {:error, %Spear.Grpc.Response{status: :already_exists}} ->
        :ok

      err ->
        err
    end
  end

  defp connect_to_persistent_subscription(%State{conn: conn, name: name, stream: stream}) do
    Spear.connect_to_persistent_subscription(conn, self(), stream, name, raw?: true)
  end

  # Get the delay between subscription attempts, in milliseconds, from app
  # config. The default value is one minute. The minimum allowed value is one
  # second.
  defp subscription_retry_interval do
    case Application.get_env(:commanded_spear_adapter, :subscription_retry_interval) do
      interval when is_integer(interval) and interval > 0 ->
        # Ensure interval is no less than one second
        max(interval, 1_000)

      _ ->
        # Default to one minute
        60_000
    end
  end

  defp event_id_to_ack(%Spear.Event{id: event_id, link: nil}), do: event_id
  defp event_id_to_ack(%Spear.Event{link: %Spear.Event{id: event_id}}), do: event_id

  defp normalize_start_from(:origin), do: :start
  defp normalize_start_from(:current), do: :end
  defp normalize_start_from(event_number), do: event_number

  defp describe(%State{name: name}), do: "Spear event store subscription #{inspect(name)}"
end
