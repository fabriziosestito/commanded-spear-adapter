defmodule Commanded.EventStore.Adapters.Extreme.Subscription do
  @moduledoc false

  use GenServer

  require Logger

  alias Commanded.EventStore.Adapters.Extreme.Mapper
  alias Commanded.EventStore.RecordedEvent
  alias Extreme.Msg, as: ExMsg

  defmodule State do
    @moduledoc false

    defstruct [
      :server,
      :last_seen_correlation_id,
      :last_seen_event_id,
      :last_seen_event_number,
      :name,
      :retry_interval,
      :serializer,
      :stream,
      :start_from,
      :subscriber_max_count,
      :subscriber,
      :subscriber_ref,
      :subscription,
      :subscription_ref,
      subscribed?: false
    ]
  end

  alias Commanded.EventStore.Adapters.Extreme.Subscription.State

  @doc """
  Start a process to create and connect a persistent connection to the Event Store
  """
  def start_link(event_store, stream, subscription_name, subscriber, serializer, opts) do
    state = %State{
      server: event_store,
      stream: stream,
      name: subscription_name,
      serializer: serializer,
      subscriber: subscriber,
      start_from: Keyword.get(opts, :start_from),
      subscriber_max_count: Keyword.get(opts, :subscriber_max_count, 1),
      retry_interval: subscription_retry_interval()
    }

    # Prevent duplicate subscriptions by stream/name
    name =
      {:global,
       {event_store, __MODULE__, stream, subscription_name, Keyword.get(opts, :index, 1)}}

    GenServer.start_link(__MODULE__, state, name: name)
  end

  @doc """
  Acknowledge receipt and successful processing of the given event.
  """
  def ack(subscription, event_number) do
    GenServer.call(subscription, {:ack, event_number})
  end

  @impl GenServer
  def init(%State{} = state) do
    %State{subscriber: subscriber} = state

    state = %State{state | subscriber_ref: Process.monitor(subscriber)}

    send(self(), :subscribe)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(
        {:ack, event_number},
        _from,
        %State{last_seen_event_number: event_number} = state
      ) do
    %State{
      subscription: subscription,
      last_seen_correlation_id: correlation_id,
      last_seen_event_id: event_id
    } = state

    Logger.debug(fn -> describe(state) <> " ack event: #{inspect(event_number)}" end)

    :ok = Extreme.PersistentSubscription.ack(subscription, event_id, correlation_id)

    state = %State{state | last_seen_event_id: nil, last_seen_event_number: nil}

    {:reply, :ok, state}
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
  def handle_info({:on_event, event, correlation_id}, %State{} = state) do
    %State{subscriber: subscriber, subscription: subscription, serializer: serializer} = state

    Logger.debug(fn -> describe(state) <> " received event: #{inspect(event)}" end)

    event_type = event.event.event_type

    event_id =
      case event.link do
        nil -> event.event.event_id
        link -> link.event_id
      end

    state =
      if event_type != nil and "$" != String.first(event_type) do
        %RecordedEvent{event_number: event_number} =
          recorded_event = Mapper.to_recorded_event(event, serializer)

        send(subscriber, {:events, [recorded_event]})

        %State{
          state
          | last_seen_correlation_id: correlation_id,
            last_seen_event_id: event_id,
            last_seen_event_number: event_number
        }
      else
        Logger.debug(fn ->
          describe(state) <> " ignoring event of type: #{inspect(event_type)}"
        end)

        :ok = Extreme.PersistentSubscription.ack(subscription, event_id, correlation_id)

        state
      end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, %State{} = state) do
    Logger.debug(fn -> describe(state) <> " down due to: #{inspect(reason)}" end)

    %State{subscriber_ref: subscriber_ref, subscription_ref: subscription_ref} = state

    case {ref, reason} do
      {^subscriber_ref, _} ->
        {:stop, {:shutdown, :subscriber_shutdown}, state}

      {^subscription_ref, :unsubscribe} ->
        {:noreply, state}

      {^subscription_ref, _} ->
        {:stop, {:shutdown, :receiver_shutdown}, state}
    end
  end

  defp subscribe(%State{} = state) do
    with :ok <- create_persistent_subscription(state),
         {:ok, subscription} <- connect_to_persistent_subscription(state) do
      :ok = notify_subscribed(state)

      %State{
        state
        | subscription: subscription,
          subscription_ref: Process.monitor(subscription),
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
      server: server,
      name: name,
      stream: stream,
      start_from: start_from,
      subscriber_max_count: subscriber_max_count
    } = state

    start_from =
      case start_from do
        :origin -> 0
        :current -> -1
        event_number -> event_number
      end

    message =
      ExMsg.CreatePersistentSubscription.new(
        subscription_group_name: name,
        event_stream_id: stream,
        resolve_link_tos: true,
        start_from: start_from,
        message_timeout_milliseconds: 10_000,
        record_statistics: false,
        live_buffer_size: 500,
        read_batch_size: 20,
        buffer_size: 500,
        max_retry_count: 10,
        prefer_round_robin: false,
        checkpoint_after_time: 1_000,
        checkpoint_max_count: 500,
        checkpoint_min_count: 1,
        subscriber_max_count: subscriber_max_count
      )

    case Extreme.execute(server, message) do
      {:ok, %ExMsg.CreatePersistentSubscriptionCompleted{result: :Success}} -> :ok
      {:error, :AlreadyExists, _response} -> :ok
      reply -> reply
    end
  end

  defp connect_to_persistent_subscription(%State{} = state) do
    %State{server: server, name: name, stream: stream} = state

    Extreme.connect_to_persistent_subscription(server, self(), name, stream, 1)
  end

  # Get the delay between subscription attempts, in milliseconds, from app
  # config. The default value is one minute. The minimum allowed value is one
  # second.
  defp subscription_retry_interval do
    case Application.get_env(:commanded_extreme_adapter, :subscription_retry_interval) do
      interval when is_integer(interval) and interval > 0 ->
        # Ensure interval is no less than one second
        max(interval, 1_000)

      _ ->
        # Default to one minute
        60_000
    end
  end

  defp describe(%State{name: name}) do
    "Extreme event store subscription #{inspect(name)}"
  end
end
