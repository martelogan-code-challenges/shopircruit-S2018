# Courtesy of: http://nathanmlong.com/2014/07/pmap-in-elixir/
defmodule Shopircruit.Parallel do
  @doc """
      iex> Parallel.map([1,2,3], &(&1*2))
      [2,4,6]
  """
  def pmap(collection, function) do
    collection
    |> Enum.map(&Task.async(fn -> function.(&1) end))
    |> Enum.map(&Task.await(&1))
  end
end
