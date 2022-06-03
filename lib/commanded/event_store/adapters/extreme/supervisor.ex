defmodule Commanded.EventStore.Adapters.Extreme.Supervisor do
  @moduledoc false

  use Supervisor

  alias Commanded.EventStore.Adapters.Extreme.Config
  alias Commanded.EventStore.Adapters.Extreme.EventPublisher
  alias Commanded.EventStore.Adapters.Extreme.SubscriptionsSupervisor

  def start_link(config) do
    event_store = Keyword.fetch!(config, :event_store)
    name = Module.concat([event_store, Supervisor])

    Supervisor.start_link(__MODULE__, config, name: name)
  end

  @impl Supervisor
  def init(config) do
    all_stream = Config.all_stream(config)
    extreme_config = Keyword.get(config, :extreme)
    spear_config = Keyword.get(config, :spear)
    serializer = Config.serializer(config)

    event_store = Keyword.fetch!(config, :event_store)
    event_publisher_name = Module.concat([event_store, EventPublisher])
    pubsub_name = Module.concat([event_store, PubSub])
    subscriptions_name = Module.concat([event_store, SubscriptionsSupervisor])
    spear_name = Module.concat([event_store, Spear.Connection])

    children = [
      {Registry, keys: :duplicate, name: pubsub_name, partitions: 1},
      %{
        id: Extreme,
        start: {Extreme, :start_link, [extreme_config, [name: event_store]]},
        restart: :permanent,
        shutdown: 5000,
        type: :worker
      },
      %{
        id: EventPublisher,
        start:
          {EventPublisher, :start_link,
           [
             {event_store, pubsub_name, all_stream, serializer},
             [name: event_publisher_name]
           ]},
        restart: :permanent,
        shutdown: 5000,
        type: :worker
      },
      {Spear.Connection,  Keyword.merge(spear_config, [name: spear_name])},
      {SubscriptionsSupervisor, name: subscriptions_name}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
