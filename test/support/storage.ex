defmodule Commanded.EventStore.Adapters.Spear.Storage do
  @moduledoc false

  def wait_for_event_store(timeout \\ 5_000)

  def wait_for_event_store(timeout) when is_integer(timeout) do
    task = Task.async(&event_store_check/0)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} ->
        result

      nil ->
        {:error, :timeout}
    end
  end

  defp event_store_check do
    headers = [Accept: "application/vnd.eventstore.atom+json"]
    options = [recv_timeout: 400]

    case HTTPoison.get("http://localhost:2113/web/index.html", headers, options) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        :timer.sleep(1_000)

        :ok

      _ ->
        :timer.sleep(1_000)

        event_store_check()
    end
  end
end
