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

  def start_subscription(
        event_store,
        conn,
        stream,
        subscription_name,
        subscriber,
        serializer,
        opts,
        index \\ 0
      ) do
    name = name(event_store)

    spec =
      subscription_spec(
        conn,
        stream,
        subscription_name,
        subscriber,
        serializer,
        opts,
        index
      )

    case DynamicSupervisor.start_child(name, spec) do
      {:ok, pid} ->
        {:ok, pid}

      {:ok, pid, _info} ->
        {:ok, pid}

      {:error, {:already_started, _pid}} ->
        case Keyword.get(opts, :concurrency_limit) do
          nil ->
            {:error, :subscription_already_exists}

          concurrency_limit when index < concurrency_limit - 1 ->
            start_subscription(
              event_store,
              conn,
              stream,
              subscription_name,
              subscriber,
              serializer,
              opts,
              index + 1
            )

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

  defp subscription_spec(
         conn,
         stream,
         subscription_name,
         subscriber,
         serializer,
         opts,
         index
       ) do
    start_args = [
      conn,
      stream,
      subscription_name,
      subscriber,
      serializer,
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
