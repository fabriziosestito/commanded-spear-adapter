defmodule Commanded.EventStore.Adapters.Spear.SnapshotTest do
  alias Commanded.EventStore.Adapters.Spear

  use Commanded.SpearTestCase
  use Commanded.EventStore.SnapshotTestCase, event_store: Spear
end
