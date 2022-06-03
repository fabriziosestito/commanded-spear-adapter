defmodule Commanded.EventStore.Adapters.Extreme.SubscriptionTest do
  alias Commanded.EventStore.Adapters.Extreme

  use Commanded.ExtremeTestCase
  use Commanded.EventStore.SubscriptionTestCase, event_store: Extreme

  defp event_store_wait(_default \\ nil), do: 5_000
end
