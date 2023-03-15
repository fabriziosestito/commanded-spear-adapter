defmodule Commanded.EventStore.Adapters.Spear.SystemEvent do
  defstruct [:data]
  @type t :: %__MODULE__{data: String.t()}
end
