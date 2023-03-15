defmodule Commanded.EventStore.Adapters.Spear.Config do
  @moduledoc false

  def all_stream(config) do
    if stream_prefix = stream_prefix(config) do
      "$ce-" <> stream_prefix
    else
      :all
    end
  end

  def stream_prefix(config) do
    if prefix = Keyword.get(config, :stream_prefix) do
      validate_prefix!(prefix)
      prefix
    end
  end

  def serializer(config) do
    Keyword.get(config, :serializer) ||
      raise ArgumentError, "expects :serializer to be configured in environment"
  end

  def content_type(config) do
    Keyword.get(config, :content_type, "application/json")
  end

  defp validate_prefix!(prefix) do
    if String.contains?(prefix, "-") do
      raise ArgumentError, ":stream_prefix cannot contain a dash (\"-\")"
    end

    :ok
  end
end
