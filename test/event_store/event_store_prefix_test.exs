defmodule Commanded.EventStore.Adapters.Spear.EventStorePrefixTest do
  alias Commanded.EventStore.Adapters.Spear
  alias Commanded.SpearTestCase

  use Commanded.EventStore.EventStorePrefixTestCase, event_store: Spear

  def start_event_store(config) do
    config =
      Keyword.update!(config, :prefix, fn prefix ->
        "commandedtest" <> prefix <> Test.UUID.uuid4()
      end)

    SpearTestCase.start_event_store(config)
  end
end
