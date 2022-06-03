defmodule Commanded.EventStore.Adapters.Extreme.ConfigTest do
  use ExUnit.Case

  alias Commanded.EventStore.Adapters.Extreme.Config

  test "should raise error when stream prefix contains \"-\"" do
    assert_raise ArgumentError, ":stream_prefix cannot contain a dash (\"-\")", fn ->
      Config.stream_prefix(stream_prefix: "invalid-prefix")
    end
  end
end
