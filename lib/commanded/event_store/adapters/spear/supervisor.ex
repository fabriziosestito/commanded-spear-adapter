defmodule Commanded.EventStore.Adapters.Spear.Supervisor do
  @moduledoc false

  use Supervisor

  alias Commanded.EventStore.Adapters.Spear.Config
  alias Commanded.EventStore.Adapters.Spear.EventPublisher
  alias Commanded.EventStore.Adapters.Spear.SubscriptionsSupervisor

  def start_link(config) do
    event_store = Keyword.fetch!(config, :event_store)
    name = Module.concat([event_store, Supervisor])

    Supervisor.start_link(__MODULE__, config, name: name)
  end

  @impl Supervisor
  def init(config) do
    all_stream = Config.all_stream(config)
    stream_prefix = Config.stream_prefix(config)
    spear_config = Keyword.get(config, :spear)
    serializer = Config.serializer(config)

    event_store = Keyword.fetch!(config, :event_store)

    event_publisher_name = Module.concat([event_store, EventPublisher])
    pubsub_name = Module.concat([event_store, PubSub])
    subscriptions_name = Module.concat([event_store, SubscriptionsSupervisor])
    conn_name = Module.concat([event_store, Spear.Connection])

    children = [
      {Registry, keys: :duplicate, name: pubsub_name, partitions: 1},
      {Spear.Connection, Keyword.merge(spear_config, name: conn_name)},
      %{
        id: EventPublisher,
        start:
          {EventPublisher, :start_link,
           [
             {conn_name, pubsub_name, all_stream, serializer, stream_prefix},
             [name: event_publisher_name]
           ]},
        restart: :permanent,
        shutdown: 5000,
        type: :worker
      },
      {SubscriptionsSupervisor, name: subscriptions_name}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
