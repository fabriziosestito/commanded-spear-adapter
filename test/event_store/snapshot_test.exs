defmodule Commanded.EventStore.Adapters.Spear.SnapshotTest do
  alias Commanded.EventStore.Adapters.Spear

  use Commanded.SpearTestCase
  use Commanded.EventStore.SnapshotTestCase, event_store: Spear

  test "persists using serializer", %{
    event_store: event_store,
    event_store_meta: event_store_meta
  } do
    event_store_meta =
      event_store_meta
      |> Map.replace!(:serializer, Spear.TermSerializer)
      |> Map.put(:content_type, "application/vnd.erlang-term-format")

    snapshot = build_snapshot_data(100)
    # use an atom somewhere to test proper deserialization
    snapshot = put_in(snapshot.data.initial_balance, :foo)
    assert :ok = event_store.record_snapshot(event_store_meta, snapshot)

    {:ok, snapshot} = event_store.read_snapshot(event_store_meta, snapshot.source_uuid)
    assert %{data: data} = snapshot
    assert %BankAccountOpened{account_number: 100, initial_balance: :foo} = data
  end
end
