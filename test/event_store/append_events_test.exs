defmodule Commanded.EventStore.Adapters.Spear.AppendEventsTest do
  alias Commanded.EventStore.Adapters.Spear

  use Commanded.SpearTestCase
  use Commanded.EventStore.AppendEventsTestCase, event_store: Spear
end
