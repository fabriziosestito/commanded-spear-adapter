defmodule Commanded.EventStore.Adapters.Extreme.AppendEventsTest do
  alias Commanded.EventStore.Adapters.Extreme

  use Commanded.ExtremeTestCase
  use Commanded.EventStore.AppendEventsTestCase, event_store: Extreme
end
