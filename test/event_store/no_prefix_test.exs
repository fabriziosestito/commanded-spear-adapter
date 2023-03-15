defmodule Commanded.EventStore.Adapters.Spear.NoPrefixTest do
  use ExUnit.Case

  alias Commanded.EventStore.Adapters.Spear, as: SpearAdapter

  alias Commanded.EventStore.{EventData, RecordedEvent}

  defmodule TestEvent do
    @derive Jason.Encoder
    defstruct [:name]
  end

  test "should use non-prefixed stream names when stream_prefix is not set" do
    event_store_meta = start_instance()

    event = fn name ->
      %EventData{
        event_type: to_string(TestEvent),
        data: %TestEvent{name: name},
        metadata: %{}
      }
    end

    stream0 = Test.UUID.uuid4()
    assert :ok = SpearAdapter.append_to_stream(event_store_meta, stream0, 0, [event.("foo")])

    stream1 = Test.UUID.uuid4()
    assert :ok = SpearAdapter.append_to_stream(event_store_meta, stream1, 0, [event.("bar")])

    # wait a bit because the $all projection is not synchronously built
    :timer.sleep(1000)

    assert [%RecordedEvent{} = first, %RecordedEvent{} = second] =
             SpearAdapter.stream_forward(event_store_meta, :all)
             # ignore other streams when running tests locally multiple times
             |> Stream.filter(fn event -> event.stream_id in [stream0, stream1] end)
             |> Enum.to_list()

    assert first.stream_id == stream0
    assert second.stream_id == stream1
  end

  defp start_instance do
    config = [
      serializer: Commanded.Serialization.JsonSerializer,
      spear: [connection_string: "esdb://localhost:2113"]
    ]

    {:ok, child_spec, event_store_meta} = SpearAdapter.child_spec(SpearApplication, config)

    for child <- child_spec do
      start_link_supervised!(child)
    end

    event_store_meta
  end
end
