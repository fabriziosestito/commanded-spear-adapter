defmodule Infra.TermSerializer do
  def serialize(term) do
    :erlang.term_to_binary(term)
  end

  def deserialize(binary, _config \\ []) do
    :erlang.binary_to_term(binary)
  end
end
