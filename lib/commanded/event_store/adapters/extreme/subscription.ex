defmodule Commanded.EventStore.Adapters.Extreme.Subscription do
  @moduledoc false

  use GenServer

  require Logger

  alias Commanded.EventStore.Adapters.Extreme.Mapper
  alias Commanded.EventStore.RecordedEvent

  defmodule State do
    @moduledoc false

    defstruct [
      :server,
      :conn,
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
  def start_link(event_store, conn, stream, subscription_name, subscriber, serializer, opts) do
    state = %State{
      server: event_store,
      conn: conn,
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
      conn: conn,
      subscription: subscription,
      last_seen_correlation_id: correlation_id,
      last_seen_event_id: event_id
    } = state

    Logger.debug(fn -> describe(state) <> " ack event: #{inspect(event_number)}" end)
    IO.inspect(state)
    :ok = Spear.ack(conn, subscription, [event_id])

    # :ok = Extreme.PersistentSubscription.ack(subscription, event_id, correlation_id)

    state = %State{state | last_seen_event_id: nil, last_seen_event_number: nil}

    {:reply, :ok, state}
  end

  # def handle_call({:ack, asd}, _from, state) do
  #   IO.inspect("badbad")
  #   IO.inspect(asd)
  #   {:reply, :ok, state}
  # end

  @impl GenServer
  def handle_info(:subscribe, state) do
    Logger.debug(fn ->
      describe(state) <>
        " to stream: #{inspect(state.stream)}, start from: #{inspect(state.start_from)}"
    end)

    {:noreply, subscribe(state)}
  end

  require Spear.Records.Persistent, as: Persistent

  @impl GenServer
  def handle_info(
        {ref, Persistent.read_resp() = raw_event},
        %State{conn: conn} = state
      ) do
    %State{subscriber: subscriber, subscription: subscription, serializer: serializer} = state

    %Spear.Event{id: event_id, type: event_type} =
      event = Spear.Event.from_read_response(raw_event, json_decoder: fn data, _ -> data end)

    Logger.debug(fn -> describe(state) <> " received event: #{inspect(event)}" end)

    state =
      if event_type != nil and "$" != String.first(event_type) do
        %RecordedEvent{event_number: event_number} =
          recorded_event = Mapper.to_recorded_event(event, serializer) |> IO.inspect()

        Process.sleep(2_000)
        send(subscriber, {:events, [recorded_event]})

        %State{
          state
          | # last_seen_correlation_id: correlation_id,
            last_seen_event_id: event_id,
            last_seen_event_number: event_number
        }
      else
        Logger.debug(fn ->
          describe(state) <> " ignoring event of type: #{inspect(event_type)}"
        end)

        :ok = Spear.ack(conn, ref, [event_id])

        state
      end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %State{conn: conn, stream: stream, name: name} = state
      ) do
    Logger.debug(fn -> describe(state) <> " down due to: #{inspect(reason)}" end)

    %State{subscriber_ref: subscriber_ref, subscription_ref: subscription_ref} = state
    Spear.delete_persistent_subscription(conn, stream, name)

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
      subscriber_max_count: subscriber_max_count
    } = state

    start_from =
      case start_from do
        :origin -> :start
        :current -> :end
        event_number -> event_number
      end

    # message =
    #   ExMsg.CreatePersistentSubscription.new(
    #     subscription_group_name: name,
    #     event_stream_id: stream,
    #     resolve_link_tos: true,
    #     start_from: start_from,
    #     message_timeout_milliseconds: 10_000,
    #     record_statistics: false,
    #     live_buffer_size: 500,
    #     read_batch_size: 20,
    #     buffer_size: 500,
    #     max_retry_count: 10,
    #     prefer_round_robin: false,
    #     checkpoint_after_time: 1_000,
    #     checkpoint_max_count: 500,
    #     checkpoint_min_count: 1,
    #     subscriber_max_count: subscriber_max_count
    #   )

    # case Extreme.execute(server, message) do
    #   {:ok, %ExMsg.CreatePersistentSubscriptionCompleted{result: :Success}} -> :ok
    #   {:error, :AlreadyExists, _response} -> :ok
    #   reply -> reply
    # end

    Spear.create_persistent_subscription(
      conn,
      stream,
      name,
      %Spear.PersistentSubscription.Settings{
        message_timeout: 10_000,
        live_buffer_size: 500,
        checkpoint_after: 1_000,
        max_checkpoint_count: 500,
        max_subscriber_count: subscriber_max_count,
        read_batch_size: 20,
        named_consumer_strategy: :RoundRobin,
        resolve_links?: true
      },
      from: start_from
    )
  end

  defp connect_to_persistent_subscription(%State{} = state) do
    %State{conn: conn, name: name, stream: stream} = state

    Spear.connect_to_persistent_subscription(conn, self(), stream, name,
      raw?: true,
      buffer_size: 1
    )
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
