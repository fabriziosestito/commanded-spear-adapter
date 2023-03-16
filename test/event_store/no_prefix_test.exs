defmodule Commanded.EventStore.Adapters.Spear.NoPrefixTest do
  use Commanded.SpearTestCase

  alias Commanded.EventStore.Adapters.Spear, as: SpearAdapter

  alias Commanded.EventStore.{EventData, RecordedEvent}

  defmodule TestEvent do
    @derive Jason.Encoder
    defstruct [:name]
  end

  @tag eventstore_config: [stream_prefix: nil]

  test "should use non-prefixed stream names when stream_prefix is not set", %{
    event_store_meta: event_store_meta
  } do
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
             |> Enum.to_list()

    assert first.stream_id == stream0
    assert second.stream_id == stream1
  end
end
