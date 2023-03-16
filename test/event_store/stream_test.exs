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
end
