defmodule Commanded.EventStore.Adapters.Spear.SubscriptionTest do
  use Commanded.SpearTestCase, async: true

  alias Commanded.EventStore.Adapters.Spear, as: SpearAdapter
  alias Commanded.EventStore.Adapters.Spear.Subscription
  alias Commanded.EventStore.{EventData, RecordedEvent}

  test "negative acknowledgements", %{event_store_meta: event_store_meta, test: test} do
    test_name = Atom.to_string(test)
    stream_id = test_name

    {:ok, subscription} =
      SpearAdapter.subscribe_to(event_store_meta, stream_id, test_name, self(), :origin, [])

    assert_receive {:subscribed, ^subscription}

    :ok =
      SpearAdapter.append_to_stream(event_store_meta, stream_id, 0, [
        build_event(1),
        build_event(2)
      ])

    assert_receive {:events, [%RecordedEvent{event_number: event_number0}]}
    :ok = Subscription.nack(subscription, event_number0, action: :park)

    assert_receive {:events, [%RecordedEvent{event_number: event_number1}]}
    assert event_number1 > event_number0
    :ok = Subscription.nack(subscription, event_number1, action: :park)

    refute_receive {:events, _}
  end

  defmodule BankAccountOpened do
    @moduledoc false

    @derive Jason.Encoder
    defstruct [:account_number, :initial_balance]
  end

  defp build_event(account_number) do
    %EventData{
      causation_id: Commanded.UUID.uuid4(),
      correlation_id: Commanded.UUID.uuid4(),
      event_type: "#{__MODULE__}.BankAccountOpened",
      data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000}
    }
  end
end
