defmodule Commanded.EventStore.Adapters.Spear.Config do
  @moduledoc false

  def all_stream(config), do: "$ce-" <> stream_prefix(config)

  def stream_prefix(config) do
    prefix =
      Keyword.get(config, :stream_prefix) ||
        raise ArgumentError, "expects :stream_prefix to be configured in environment"

    case String.contains?(prefix, "-") do
      true -> raise ArgumentError, ":stream_prefix cannot contain a dash (\"-\")"
      false -> prefix
    end
  end

  def serializer(config) do
    Keyword.get(config, :serializer) ||
      raise ArgumentError, "expects :serializer to be configured in environment"
  end

  def content_type(config) do
    Keyword.get(config, :content_type, "application/json")
  end
end
