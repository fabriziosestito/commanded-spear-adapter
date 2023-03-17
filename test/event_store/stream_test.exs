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

    assert :ok = SpearAdapter.subscribe(event_store_meta, :all)

    assert :ok =
             SpearAdapter.append_to_stream(event_store_meta, Test.UUID.uuid4(), 0, [event.("foo")])

    assert :ok =
             SpearAdapter.append_to_stream(event_store_meta, Test.UUID.uuid4(), 0, [event.("bar")])

    # wait for the all stream to be built
    assert_receive {:events, [%RecordedEvent{}]}
    assert_receive {:events, [%RecordedEvent{}]}

    assert [%RecordedEvent{data: first}, %RecordedEvent{data: second}] =
             SpearAdapter.stream_forward(event_store_meta, :all) |> Enum.to_list()

    assert %TestEvent{name: "foo"} = first
    assert %TestEvent{name: "bar"} = second
  end

  test "parses the system type properly", %{
    event_store_meta: event_store_meta,
    event_store_db_uri: event_store_db_uri
  } do
    conn = start_link_supervised!({Spear.Connection, [connection_string: event_store_db_uri]})

    assert :ok = SpearAdapter.subscribe(event_store_meta, :all)

    assert %Spear.Event{id: event_b_id} = insert(event_store_meta, conn, "b0", "teststream-b")

    assert %Spear.Event{id: _event_c_id} =
             insert_link(event_store_meta, conn, {0, "teststream-b"}, "stream_c")

    # # wait for the all stream to be built
    # second time is the linked event, but the id of the linked event is not event_c_id for some reason
    assert_receive {:events, [%RecordedEvent{event_id: ^event_b_id}]}
    assert_receive {:events, [%RecordedEvent{event_id: ^event_b_id}]}

    [first, second] =
      SpearAdapter.stream_forward(event_store_meta, :all)
      |> Enum.to_list()

    stream_prefix = Map.fetch!(event_store_meta, :stream_prefix)
    all_stream = "$ce-#{stream_prefix}"

    assert %RecordedEvent{
             stream_id: "teststream-b",
             stream_version: 1,
             metadata: %{link: link}
           } = first

    assert %RecordedEvent{
             stream_id: ^all_stream,
             stream_version: 1,
             event_type: "$>"
           } = link

    assert %RecordedEvent{
             stream_id: "teststream-b",
             stream_version: 1,
             metadata: %{link: link}
           } = second

    assert %RecordedEvent{
             stream_id: ^all_stream,
             stream_version: 2,
             event_type: "$>"
           } = link
  end

  defp insert(event_store_meta, conn, name, stream) do
    event_type = "#{__MODULE__}.TestEvent"
    event = Spear.Event.new(event_type, %TestEvent{name: name})

    stream_prefixed = Map.fetch!(event_store_meta, :stream_prefix) <> "-" <> stream
    assert Spear.append([event], conn, stream_prefixed) == :ok
    event
  end

  defp insert_link(event_store_meta, conn, {index, source_stream}, target_stream) do
    prefix = Map.fetch!(event_store_meta, :stream_prefix)

    event =
      Spear.Event.new("$>", "#{index}@#{prefix <> "-" <> source_stream}",
        content_type: "application/vnd.erlang-term-format"
      )

    target_stream_prefixed = prefix <> "-" <> target_stream
    assert Spear.append([event], conn, target_stream_prefixed) == :ok
    event
  end
end
