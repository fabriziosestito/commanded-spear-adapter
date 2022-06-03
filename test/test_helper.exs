alias Commanded.EventStore.Adapters.Extreme.Storage

:ok = Storage.wait_for_event_store(:timer.minutes(1))

ExUnit.start()
