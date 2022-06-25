defmodule BohTest do
  use ExUnit.Case
  import Commanded.SharedTestCase

  alias Commanded.EventStore.Adapters.Extreme.Mapper

  test "asd2" do
    {:ok, conn} = Spear.Connection.start_link(connection_string: "esdb://localhost:2113")
    event1 = Spear.Event.new("test", %{"event" => 1})
    event2 = Spear.Event.new("test", %{"event" => 2})
    event3 = Spear.Event.new("test", %{"event" => 3})

    stream = "test-#{UUID.uuid4()}"
    group = UUID.uuid4()
    Spear.append([event1], conn, stream)

    :ok =
      Spear.create_persistent_subscription(
        conn,
        "$ce-test",
        group,
        %Spear.PersistentSubscription.Settings{
          named_consumer_strategy: :Pinned,
          resolve_links?: true
        },
        filter: Spear.Filter.exclude_system_events(),
        from: :end
      )

    {:ok, subscription} =
      Spear.connect_to_persistent_subscription(conn, self(), "$ce-test", group, raw?: false)

    Spear.append([event2], conn, stream)
    Spear.append([event3], conn, stream)

    assert_receive event_received_1
    IO.inspect(event_received_1)
    :ok = Spear.ack(conn, subscription, [event_received_1.link.id])

    assert_receive event_received_2
    IO.inspect(event_received_2)
    :ok = Spear.ack(conn, subscription, [event_received_2.id])
  end
end
