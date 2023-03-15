defmodule Commanded.EventStore.Adapters.Spear.EventStorePrefixTest do
  alias Commanded.EventStore.Adapters.Spear
  alias Commanded.SpearTestCase

  use ExUnit.Case

  setup_all do
    %{event_store_db_uri: event_store_db_uri} = TestUtils.EventStoreDBContainer.start()
    Process.put({__MODULE__, :event_store_db_uri}, event_store_db_uri)
    :ok
  end

  use Commanded.EventStore.EventStorePrefixTestCase, event_store: Spear

  def start_event_store(config) do
    name = Keyword.fetch!(config, :name)
    stream_prefix = Keyword.fetch!(config, :prefix)
    event_store_db_uri = Process.get({__MODULE__, :event_store_db_uri})

    %{event_store_meta: event_store_meta} =
      SpearTestCase.start_event_store(name, stream_prefix, event_store_db_uri)

    {:ok, event_store_meta}
  end
end
