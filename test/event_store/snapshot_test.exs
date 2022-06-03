defmodule Commanded.EventStore.Adapters.Extreme.SnapshotTest do
  alias Commanded.EventStore.Adapters.Extreme

  use Commanded.ExtremeTestCase
  use Commanded.EventStore.SnapshotTestCase, event_store: Extreme
end
