defmodule Commanded.EventStore.Adapters.Spear.SerializationTest do
  use ExUnit.Case

  alias Commanded.EventStore.{
    EventData,
    RecordedEvent
  }

  alias Commanded.EventStore.Adapters.Spear
  alias Commanded.SpearTestCase

  setup do
    {:ok, event_store_meta} =
      SpearTestCase.start_event_store(
        serializer: Commanded.EventStore.Adapters.Spear.TermSerializer,
        content_type: "application/vnd.erlang-term-format"
      )

    [event_store_meta: event_store_meta]
  end

  test "should append and stream events in erlang term", %{event_store_meta: event_store_meta} do
    stream = Test.UUID.uuid4()

    data = %{
      tonio: "tonino"
    }

    metadata = %{
      wanda: "wandalorian"
    }

    event = %EventData{
      causation_id: Test.UUID.uuid4(),
      correlation_id: Test.UUID.uuid4(),
      event_type: "test",
      data: data,
      metadata: metadata
    }

    :ok = Spear.append_to_stream(event_store_meta, stream, 0, [event])

    assert [%RecordedEvent{data: ^data, metadata: ^metadata}] =
             Spear.stream_forward(event_store_meta, stream)
  end
end
