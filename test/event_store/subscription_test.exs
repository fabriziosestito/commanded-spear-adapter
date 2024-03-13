defmodule Commanded.EventStore.Adapters.Spear.SubscriptionTest do
  alias Commanded.EventStore.Adapters.Spear, as: SpearAdapter

  use Commanded.SpearTestCase, async: true
  use Commanded.EventStore.Spear.SubscriptionTestCase, event_store: SpearAdapter

  defp event_store_wait(_default \\ nil), do: 5_000
end
