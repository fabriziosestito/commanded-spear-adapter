defmodule Commanded.EventStore.Adapters.Spear.AppendEventsTest do
  alias Commanded.EventStore.Adapters.Spear

  use Commanded.SpearTestCase, async: true
  use Commanded.EventStore.AppendEventsTestCase, event_store: Spear
end
