defmodule Commanded.EventStore.Adapters.Spear.SubscriptionTest do
  alias Commanded.EventStore.Adapters.Spear

  use Commanded.SpearTestCase
  use Commanded.EventStore.Spear.SubscriptionTestCase, event_store: Spear

  defp event_store_wait(_default \\ nil), do: 5_000
end
