defmodule TestUtils.EventStoreDBContainer do
  @moduledoc false

  alias Excontainers.{Container, ResourcesReaper}

  @http_port 2113
  @wait_strategy Docker.CommandWaitStrategy.new(["curl", "-f", "localhost:2113/ping"])

  def new(opts \\ []) do
    image_version = Keyword.get(opts, :version, "23.10.0")

    image_os =
      case :erlang.system_info(:system_architecture) |> IO.iodata_to_binary() do
        "aarch64" <> _ -> "alpha-arm64v8"
        _ -> "jammy"
      end

    image_tag = "eventstore/eventstore:#{image_version}-#{image_os}"

    Docker.Container.new(
      image_tag,
      exposed_ports: [@http_port],
      environment: %{
        "EVENTSTORE_CLUSTER_SIZE" => 1,
        "EVENTSTORE_RUN_PROJECTIONS" => "System",
        "EVENTSTORE_START_STANDARD_PROJECTIONS" => true,
        "EVENTSTORE_EXT_TCP_PORT" => 1113,
        "EVENTSTORE_HTTP_PORT" => 2113,
        "EVENTSTORE_INSECURE" => true,
        "EVENTSTORE_ENABLE_EXTERNAL_TCP" => false,
        "EVENTSTORE_ENABLE_ATOM_PUB_OVER_HTTP" => false
      },
      wait_strategy: @wait_strategy
    )
  end

  def port(pid), do: with({:ok, port} <- Container.mapped_port(pid, @http_port), do: port)

  def connection_string(pid), do: "esdb://localhost:#{port(pid)}"

  def start do
    {:ok, pid} = Container.start_link(new())
    container_id = Container.container_id(pid)

    ExUnit.Callbacks.on_exit(container_id, fn ->
      Docker.Containers.stop(container_id, timeout_seconds: 2)
    end)

    # this is only useful if ResourcesReaper is actually started in test_helper.exs
    # otherwise, you have to run docker container prune from time to time
    ResourcesReaper.register({"id", container_id})

    %{event_store_db_uri: connection_string(pid), event_store_db_pid: pid}
  end
end
