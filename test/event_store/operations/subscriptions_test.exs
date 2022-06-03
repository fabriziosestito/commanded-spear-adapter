defmodule Commanded.EventStore.Adapters.Extreme.SubscriptionsTest do
  use ExUnit.Case

  alias Extreme.Msg, as: ExMsg

  setup do
    config = config()

    {:ok, pid} = Extreme.start_link(config)

    [config: config, server: pid]
  end

  @moduletag :skip

  describe "persistent subscriptions" do
    setup [:append_events_to_stream]

    test "subscribe to `$all` stream", %{server: server} do
      name = "test-subscription-#{UUID.uuid4()}"

      :ok = create_persistent_subscription(server, name, "$all")

      {:ok, subscription} = connect_to_persistent_subscription(server, name, "$all")

      for event_number <- 1..3 do
        assert_receive {:on_event, %Extreme.Msg.ResolvedIndexedEvent{} = event, correlation_id}

        %Extreme.Msg.ResolvedIndexedEvent{
          event: %Extreme.Msg.EventRecord{
            event_id: event_id,
            event_type: event_type,
            data: data
          }
        } = event

        assert Jason.decode!(data) == %{"event" => event_number}
        assert event_type == "test-event"

        :ok = Extreme.PersistentSubscription.ack(subscription, event_id, correlation_id)
      end

      refute_receive {:on_event, _event, _correlation_id}
    end
  end

  defp append_events_to_stream(context) do
    %{server: server} = context

    stream_id = UUID.uuid4()

    :ok = write_events(server, stream_id)

    [stream_id: stream_id]
  end

  defp write_events(server, stream_id, expected_version \\ -1) do
    events =
      Enum.map(1..3, fn event_number ->
        ExMsg.NewEvent.new(
          event_id: UUID.uuid4() |> UUID.string_to_binary!(),
          event_type: "test-event",
          data_content_type: 0,
          metadata_content_type: 0,
          data: Jason.encode!(%{"event" => event_number}),
          metadata: "{}"
        )
      end)

    message =
      ExMsg.WriteEvents.new(
        event_stream_id: stream_id,
        expected_version: expected_version,
        events: events,
        require_master: false
      )

    execute(server, message)
  end

  defp read_events(server, stream_id, from_event_number \\ 0, max_count \\ 1_000) do
    message =
      ExMsg.ReadStreamEvents.new(
        event_stream_id: stream_id,
        from_event_number: from_event_number,
        max_count: max_count,
        resolve_link_tos: true,
        require_master: false
      )

    with {:ok, %ExMsg.ReadStreamEventsCompleted{events: events}} <-
           Extreme.execute(server, message) do
      {:ok, events}
    end
  end

  defp create_persistent_subscription(server, name, stream_id, start_from \\ 0) do
    message =
      ExMsg.CreatePersistentSubscription.new(
        subscription_group_name: name,
        event_stream_id: stream_id,
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
        subscriber_max_count: 1
      )

    with {:ok, %ExMsg.CreatePersistentSubscriptionCompleted{result: :Success}} <-
           Extreme.execute(server, message) do
      :ok
    end
  end

  defp connect_to_persistent_subscription(server, name, stream) do
    Extreme.connect_to_persistent_subscription(server, self(), name, stream, 1)
  end

  defp execute(server, message) do
    with {:ok, _response} <- Extreme.execute(server, message) do
      :ok
    end
  end

  def config do
    [
      db_type: :node,
      host: "localhost",
      port: 1113,
      username: "admin",
      password: "changeit",
      reconnect_delay: 2_000,
      max_attempts: :infinity
    ]
  end
end
