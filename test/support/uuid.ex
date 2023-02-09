defmodule Test.UUID do
  @moduledoc false

  def uuid4 do
    String.replace(Commanded.UUID.uuid4(), "-", "")
  end
end
