defmodule Commanded.EventStore.Adapters.Spear.EventStorePrefixTest do
  alias Commanded.EventStore.Adapters.Spear
  alias Commanded.SpearTestCase

  use Commanded.EventStore.EventStorePrefixTestCase, event_store: Spear

  def start_event_store(config) do
    config =
      Keyword.update!(config, :prefix, fn prefix ->
        uuid = String.replace(Commanded.UUID.uuid4(), "-", "")
        "commandedtest" <> prefix <> uuid
      end)

    SpearTestCase.start_event_store(config)
  end
end
