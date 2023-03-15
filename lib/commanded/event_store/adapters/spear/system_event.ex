defmodule Commanded.EventStore.Adapters.Spear.SystemEvent do
  @moduledoc """
  This event is used when an `Spear.Event` with a type that starts with '$' is
  being converted. The serializer is not called and the data and metadata is
  returned as-is.
  """

  defstruct [:data]
  @type t :: %__MODULE__{data: String.t()}
end
