defmodule Commanded.SpearTestCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Commanded.EventStore.Adapters.Spear

  setup_all do
    %{event_store_db_uri: _event_store_db_uri} = TestUtils.EventStoreDBContainer.start()
  end

  setup %{module: module, test: test, event_store_db_uri: event_store_db_uri} = ctx do
    opts = Map.get(ctx, :eventstore_config, [])
    start_event_store(module, Macro.to_string(test), event_store_db_uri, opts)
  end

  def start_event_store(name, stream_prefix, event_store_db_uri, opts \\ []) do
    config =
      Keyword.merge(
        [
          name: name,
          serializer: Commanded.Serialization.JsonSerializer,
          stream_prefix: stream_prefix,
          spear: [connection_string: event_store_db_uri]
        ],
        opts
      )

    {:ok, child_spec, event_store_meta} = Spear.child_spec(SpearApplication, config)

    for child <- child_spec do
      start_link_supervised!(child)
    end

    %{event_store_meta: event_store_meta}
  end
end
