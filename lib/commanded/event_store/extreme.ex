defmodule Commanded.EventStore.Adapters.Extreme do
  @moduledoc """
  Adapter to use [Event Store](https://eventstore.com/), via the Extreme TCP
  client, with Commanded.

  Please check the [Getting started](getting-started.html) guide to learn more.
  """

  @behaviour Commanded.EventStore.Adapter

  require Logger

  alias Commanded.EventStore.Adapters.Extreme.Config
  alias Commanded.EventStore.Adapters.Extreme.Mapper
  alias Commanded.EventStore.Adapters.Extreme.Subscription
  alias Commanded.EventStore.Adapters.Extreme.SubscriptionsSupervisor
  alias Commanded.EventStore.EventData
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.EventStore.SnapshotData
  alias Commanded.EventStore.TypeProvider
  alias Extreme.Msg, as: ExMsg

  @impl Commanded.EventStore.Adapter
  def child_spec(application, config) do
    event_store =
      case Keyword.get(config, :name) do
        nil -> Module.concat([application, Extreme])
        name -> Module.concat([name, Extreme])
      end

    conn = Module.concat([event_store, Spear.Connection])

    # Rename `prefix` config to `stream_prefix`
    config =
      case Keyword.pop(config, :prefix) do
        {nil, config} -> config
        {prefix, config} -> Keyword.put(config, :stream_prefix, prefix)
      end

    child_spec = [
      Supervisor.child_spec(
        {Commanded.EventStore.Adapters.Extreme.Supervisor,
         Keyword.put(config, :event_store, event_store)},
        id: event_store
      )
    ]

    adapter_meta = %{
      all_stream: Config.all_stream(config),
      event_store: event_store,
      conn: conn,
      stream_prefix: Config.stream_prefix(config),
      serializer: Config.serializer(config)
    }

    {:ok, child_spec, adapter_meta}
  end

  @impl Commanded.EventStore.Adapter
  def append_to_stream(adapter_meta, stream_uuid, expected_version, events) do
    stream = stream_name(adapter_meta, stream_uuid)

    Logger.debug(fn ->
      "Extreme event store attempting to append to stream " <>
        inspect(stream) <> " " <> inspect(length(events)) <> " event(s)"
    end)

    add_to_stream(adapter_meta, stream, expected_version, events)
  end

  @impl Commanded.EventStore.Adapter
  def stream_forward(
        adapter_meta,
        stream_uuid,
        start_version \\ 0,
        read_batch_size \\ 1_000
      ) do
    stream = stream_name(adapter_meta, stream_uuid)
    start_version = normalize_start_version(start_version)

    case execute_read(adapter_meta, stream, start_version, read_batch_size, :forward) do
      {:ok, events, true} ->
        events

      {:ok, events, false} ->
        Stream.concat(
          events,
          execute_stream_forward(
            adapter_meta,
            stream,
            start_version + length(events),
            read_batch_size
          )
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Commanded.EventStore.Adapter
  def subscribe(adapter_meta, :all), do: subscribe(adapter_meta, "$all")

  @impl Commanded.EventStore.Adapter
  def subscribe(adapter_meta, stream_uuid) do
    event_store = server_name(adapter_meta)
    pubsub_name = Module.concat([event_store, PubSub])

    with {:ok, _} <- Registry.register(pubsub_name, stream_uuid, []) do
      :ok
    end
  end

  @impl Commanded.EventStore.Adapter
  def subscribe_to(adapter_meta, :all, subscription_name, subscriber, start_from, opts) do
    event_store = server_name(adapter_meta)
    stream = Map.fetch!(adapter_meta, :all_stream)
    serializer = serializer(adapter_meta)
    opts = subscription_options(opts, start_from)

    SubscriptionsSupervisor.start_subscription(
      event_store,
      stream,
      subscription_name,
      subscriber,
      serializer,
      opts
    )
  end

  @impl Commanded.EventStore.Adapter
  def subscribe_to(adapter_meta, stream_uuid, subscription_name, subscriber, start_from, opts) do
    event_store = server_name(adapter_meta)
    stream = stream_name(adapter_meta, stream_uuid)
    serializer = serializer(adapter_meta)
    opts = subscription_options(opts, start_from)

    SubscriptionsSupervisor.start_subscription(
      event_store,
      stream,
      subscription_name,
      subscriber,
      serializer,
      opts
    )
  end

  @impl Commanded.EventStore.Adapter
  def ack_event(_adapter_meta, subscription, %RecordedEvent{event_number: event_number}) do
    Subscription.ack(subscription, event_number)
  end

  @impl Commanded.EventStore.Adapter
  def unsubscribe(adapter_meta, subscription) do
    event_store = server_name(adapter_meta)

    SubscriptionsSupervisor.stop_subscription(event_store, subscription)
  end

  @impl Commanded.EventStore.Adapter
  def delete_subscription(adapter_meta, :all, subscription_name) do
    event_store = server_name(adapter_meta)
    stream = Map.fetch!(adapter_meta, :all_stream)

    delete_persistent_subscription(event_store, stream, subscription_name)
  end

  @impl Commanded.EventStore.Adapter
  def delete_subscription(adapter_meta, stream_uuid, subscription_name) do
    event_store = server_name(adapter_meta)
    stream = stream_name(adapter_meta, stream_uuid)

    delete_persistent_subscription(event_store, stream, subscription_name)
  end

  @impl Commanded.EventStore.Adapter
  def read_snapshot(adapter_meta, source_uuid) do
    stream = snapshot_stream_name(adapter_meta, source_uuid)

    Logger.debug(fn -> "Extreme event store read snapshot from stream: " <> inspect(stream) end)

    case execute_read(adapter_meta, stream, -1, 1, :backward) do
      {:ok, [recorded_event], _end_of_stream?} ->
        {:ok, to_snapshot_data(recorded_event)}

      {:error, :stream_not_found} ->
        {:error, :snapshot_not_found}

      err ->
        Logger.error(fn -> "Extreme event store error reading snapshot: " <> inspect(err) end)
        err
    end
  end

  @impl Commanded.EventStore.Adapter
  def record_snapshot(adapter_meta, %SnapshotData{} = snapshot) do
    event_data = to_event_data(snapshot)
    stream = snapshot_stream_name(adapter_meta, snapshot.source_uuid)

    Logger.debug(fn -> "Extreme event store record snapshot to stream: " <> inspect(stream) end)

    case add_to_stream(adapter_meta, stream, :any_version, [event_data]) do
      {:ok, _} -> :ok
      err -> err
    end
  end

  @impl Commanded.EventStore.Adapter
  def delete_snapshot(adapter_meta, source_uuid) do
    server = server_name(adapter_meta)
    stream = snapshot_stream_name(adapter_meta, source_uuid)

    msg = delete_stream_msg(stream, false)

    case Extreme.execute(server, msg) do
      {:ok, _} -> :ok
      err -> err
    end
  end

  defp execute_stream_forward(adapter_meta, stream, start_version, read_batch_size) do
    Stream.resource(
      fn -> {start_version, false} end,
      fn {next_version, halt?} = acc ->
        case halt? do
          true ->
            {:halt, acc}

          false ->
            case execute_read(
                   adapter_meta,
                   stream,
                   next_version,
                   read_batch_size,
                   :forward
                 ) do
              {:ok, events, end_of_stream?} ->
                acc = {next_version + length(events), end_of_stream?}

                {events, acc}
            end
        end
      end,
      fn _ -> :ok end
    )
  end

  defp stream_name(adapter_meta, stream_uuid),
    do: Map.fetch!(adapter_meta, :stream_prefix) <> "-" <> stream_uuid

  defp snapshot_stream_name(adapter_meta, source_uuid),
    do: Map.fetch!(adapter_meta, :stream_prefix) <> "snapshot-" <> source_uuid

  defp normalize_start_version(0), do: 0
  defp normalize_start_version(start_version), do: start_version - 1

  defp to_snapshot_data(%RecordedEvent{} = event) do
    %RecordedEvent{data: snapshot} = event

    data =
      snapshot.source_type
      |> String.to_existing_atom()
      |> struct(snapshot.data)
      |> Commanded.Serialization.JsonDecoder.decode()

    %SnapshotData{snapshot | data: data, created_at: event.created_at}
  end

  defp to_event_data(%SnapshotData{} = snapshot) do
    %EventData{
      event_type: TypeProvider.to_string(snapshot),
      data: snapshot
    }
  end

  defp add_to_stream(adapter_meta, stream, :stream_exists, events) do
    case execute_read(adapter_meta, stream, 0, 1, :forward) do
      {:ok, _events, _end_of_stream?} ->
        add_to_stream(adapter_meta, stream, :any_version, events)

      {:error, :stream_not_found} ->
        {:error, :stream_does_not_exist}

      {:error, _error} = reply ->
        reply
    end
  end

  defp add_to_stream(adapter_meta, stream, expected_version, events) do
    conn = conn_name(adapter_meta)
    serializer = serializer(adapter_meta)

    events
    |> Stream.map(fn event ->
      event.event_type
      |> Spear.Event.new(
        event.data,
        custom_metadata:
          event.metadata
          |> add_causation_id(event.causation_id)
          |> add_correlation_id(event.correlation_id)
          |> serializer.serialize()
      )
      |> Spear.Event.to_proposed_message(%{"application/json" => &serializer.serialize/1})
    end)
    |> Spear.append(conn, stream, expect: expected_version(expected_version))
    |> case do
      :ok ->
        :ok

      {:error, %Spear.ExpectationViolation{} = detail} ->
        Logger.warn(fn ->
          "Extreme event store wrong expected version " <>
            inspect(expected_version) <> " due to: " <> inspect(detail)
        end)

        case expected_version do
          :no_stream -> {:error, :stream_exists}
          :stream_exists -> {:error, :stream_does_not_exist}
          _expected_version -> {:error, :wrong_expected_version}
        end

      reply ->
        reply
    end
  end

  defp delete_stream_msg(stream, hard_delete) do
    ExMsg.DeleteStream.new(
      event_stream_id: stream,
      expected_version: -2,
      require_master: false,
      hard_delete: hard_delete
    )
  end

  defp execute_read(
         adapter_meta,
         stream,
         start_version,
         count,
         direction,
         read_events \\ []
       ) do
    server = server_name(adapter_meta)
    remaining_count = count - length(read_events)
    read_request = read_events(stream, start_version, remaining_count, direction)

    serializer = Map.fetch!(adapter_meta, :serializer)

    case Extreme.execute(server, read_request) do
      {:ok, %ExMsg.ReadStreamEventsCompleted{} = result} ->
        %ExMsg.ReadStreamEventsCompleted{
          is_end_of_stream: end_of_stream?,
          events: events
        } = result

        read_events = read_events ++ events

        if end_of_stream? || length(read_events) == count do
          recorded_events = Enum.map(read_events, &Mapper.to_recorded_event(&1, serializer))

          {:ok, recorded_events, end_of_stream?}
        else
          # can occur with soft deleted streams
          start_version =
            case direction do
              :forward -> result.next_event_number
              :backward -> result.last_event_number
            end

          execute_read(
            adapter_meta,
            stream,
            start_version,
            remaining_count,
            direction,
            read_events
          )
        end

      {:error, :NoStream, _} ->
        {:error, :stream_not_found}

      err ->
        err
    end
  end

  defp read_events(stream, from_event_number, max_count, direction) do
    msg_type =
      if :forward == direction, do: ExMsg.ReadStreamEvents, else: ExMsg.ReadStreamEventsBackward

    msg_type.new(
      event_stream_id: stream,
      from_event_number: from_event_number,
      max_count: max_count,
      resolve_link_tos: true,
      require_master: false
    )
  end

  defp add_causation_id(metadata, causation_id),
    do: add_to_metadata(metadata, "$causationId", causation_id)

  defp add_correlation_id(metadata, correlation_id),
    do: add_to_metadata(metadata, "$correlationId", correlation_id)

  defp add_to_metadata(metadata, key, value) when is_nil(metadata),
    do: add_to_metadata(%{}, key, value)

  defp add_to_metadata(metadata, _key, value) when is_nil(value), do: metadata

  defp add_to_metadata(metadata, key, value), do: Map.put(metadata, key, value)

  defp delete_persistent_subscription(server, stream, name) do
    Logger.debug(fn ->
      "Attempting to delete persistent subscription named #{inspect(name)} on stream #{inspect(stream)}"
    end)

    message =
      ExMsg.DeletePersistentSubscription.new(
        subscription_group_name: name,
        event_stream_id: stream
      )

    case Extreme.execute(server, message) do
      {:ok, %ExMsg.DeletePersistentSubscriptionCompleted{result: :Success}} ->
        :ok

      {:error, :DoesNotExist, %ExMsg.DeletePersistentSubscriptionCompleted{}} ->
        {:error, :subscription_not_found}

      {:error, :Fail, %ExMsg.DeletePersistentSubscriptionCompleted{}} ->
        {:error, :failed_to_delete}

      {:error, :AccessDenied, %ExMsg.DeletePersistentSubscriptionCompleted{}} ->
        {:error, :access_denied}

      reply ->
        reply
    end
  end

  defp subscription_options(opts, start_from) do
    Keyword.put(opts, :start_from, start_from)
  end

  # Event store supports the following special values for expected version:
  #
  #  -2 states that this write should never conflict and should always succeed.
  #  -1 states that the stream should not exist at the time of the writing.
  #  0 states that the stream should exist but should be empty.
  #
  #  Any other integer value represents the version of the stream you expect.
  #
  defp expected_version(:any_version), do: :any
  defp expected_version(:no_stream), do: :empty
  defp expected_version(:stream_exists), do: :exists
  defp expected_version(0), do: :empty

  defp expected_version(expected_version), do: expected_version - 1

  defp serializer(adapter_meta), do: Map.fetch!(adapter_meta, :serializer)
  defp server_name(adapter_meta), do: Map.fetch!(adapter_meta, :event_store)
  defp conn_name(adapter_meta), do: Map.fetch!(adapter_meta, :conn)
end
