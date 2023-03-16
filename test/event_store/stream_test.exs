defmodule Commanded.EventStore.Adapters.Spear.StreamTest do
  use Commanded.SpearTestCase, async: true

  alias Commanded.EventStore.Adapters.Spear, as: SpearAdapter

  alias Commanded.EventStore.{EventData, RecordedEvent}

  defmodule TestEvent do
    @derive Jason.Encoder
    defstruct [:name]
  end

  test "should read from the all stream properly", %{event_store_meta: event_store_meta} do
    event = fn name ->
      %EventData{
        event_type: "#{__MODULE__}.TestEvent",
        data: %TestEvent{name: name},
        metadata: %{}
      }
    end

    assert :ok =
             SpearAdapter.append_to_stream(event_store_meta, Test.UUID.uuid4(), 0, [event.("foo")])

    assert :ok =
             SpearAdapter.append_to_stream(event_store_meta, Test.UUID.uuid4(), 0, [event.("bar")])

    # wait a bit because the $ce-xxx projection is not synchronously built
    :timer.sleep(1000)

    assert [%RecordedEvent{data: first}, %RecordedEvent{data: second}] =
             SpearAdapter.stream_forward(event_store_meta, :all) |> Enum.to_list()

    assert %TestEvent{name: "foo"} = first
    assert %TestEvent{name: "bar"} = second
  end

  @tag eventstore_config: [stream_prefix: nil]

  test "parses the link type as Spear.Event", %{
    event_store_meta: event_store_meta,
    event_store_db_uri: event_store_db_uri
  } do
    conn = start_link_supervised!({Spear.Connection, [connection_string: event_store_db_uri]})

    insert(conn, "b0", "teststream-b")
    insert_link(conn, {0, "teststream-b"}, "stream_c")

    [first, second] =
      SpearAdapter.stream_forward(event_store_meta, :all)
      |> Enum.to_list()

    assert %RecordedEvent{
             stream_id: "teststream-b",
             stream_version: 1,
             metadata: metadata
           } = first

    refute Map.has_key?(metadata, :link)

    assert %RecordedEvent{
             stream_id: "teststream-b",
             stream_version: 1,
             metadata: %{link: link}
           } = second

    assert %RecordedEvent{
             stream_id: "stream_c",
             stream_version: 1,
             event_type: "$>"
           } = link
  end

  defp insert(conn, name, stream) do
    event_type = "#{__MODULE__}.TestEvent"
    event = Spear.Event.new(event_type, %TestEvent{name: name})

    assert Spear.append([event], conn, stream) == :ok
    event
  end

  defp insert_link(conn, {index, source_stream}, target_stream) do
    event =
      Spear.Event.new("$>", "#{index}@#{source_stream}",
        content_type: "application/vnd.erlang-term-format"
      )

    assert Spear.append([event], conn, target_stream) == :ok
    event
  end
end
