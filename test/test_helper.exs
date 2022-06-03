alias Commanded.EventStore.Adapters.Spear.Storage

:ok = Storage.wait_for_event_store(:timer.minutes(1))

ExUnit.start()
