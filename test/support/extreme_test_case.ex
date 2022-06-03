defmodule Commanded.ExtremeTestCase do
  use ExUnit.CaseTemplate

  alias Commanded.EventStore.Adapters.Extreme

  setup do
    {:ok, event_store_meta} = start_event_store()

    [event_store_meta: event_store_meta]
  end

  def start_event_store(config \\ []) do
    config =
      Keyword.merge(
        [
          serializer: Commanded.Serialization.JsonSerializer,
          stream_prefix: "commandedtest" <> UUID.uuid4(:hex),
          extreme: [
            db_type: :node,
            host: "localhost",
            port: 1113,
            username: "admin",
            password: "changeit",
            reconnect_delay: 2_000,
            max_attempts: :infinity
          ],
          spear: [
            connection_string: "esdb://localhost:2113"
          ]
        ],
        config
      )

    {:ok, child_spec, event_store_meta} = Extreme.child_spec(ExtremeApplication, config)

    for child <- child_spec do
      start_supervised!(child)
    end

    {:ok, event_store_meta}
  end
end
