defmodule Commanded.EventStore.Adapters.Spear.SubscriptionsSupervisor do
  @moduledoc false

  use DynamicSupervisor

  require Logger

  alias Commanded.EventStore.Adapters.Spear.Subscription

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, [], opts)
  end

  @impl DynamicSupervisor
  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_subscription(args) when is_map(args) do
    %{event_store: event_store} = args

    args = Map.put_new(args, :index, 0)
    name = name(event_store)

    spec = subscription_spec(args)

    case DynamicSupervisor.start_child(name, spec) do
      {:ok, pid} ->
        {:ok, pid}

      {:ok, pid, _info} ->
        {:ok, pid}

      {:error, {:already_started, _pid}} ->
        case Keyword.get(args.opts, :concurrency_limit) do
          nil ->
            {:error, :subscription_already_exists}

          concurrency_limit when args.index < concurrency_limit - 1 ->
            start_subscription(%{args | index: args.index + 1})

          _ ->
            {:error, :too_many_subscribers}
        end

      reply ->
        reply
    end
  end

  def stop_subscription(event_store, subscription) do
    name = name(event_store)

    DynamicSupervisor.terminate_child(name, subscription)
  end

  defp subscription_spec(args) when is_map(args) do
    %{
      event_store: event_store,
      conn: conn,
      stream: stream,
      subscription_name: subscription_name,
      subscriber: subscriber,
      serializer: serializer,
      stream_prefix: stream_prefix,
      opts: opts,
      index: index
    } = args

    start_args = [
      event_store,
      conn,
      stream,
      subscription_name,
      subscriber,
      serializer,
      stream_prefix,
      Keyword.put(opts, :index, index)
    ]

    %{
      id: {Subscription, stream, subscription_name, index},
      start: {Subscription, :start_link, start_args},
      restart: :temporary,
      shutdown: 5_000,
      type: :worker
    }
  end

  defp name(event_store), do: Module.concat([event_store, __MODULE__])
end
