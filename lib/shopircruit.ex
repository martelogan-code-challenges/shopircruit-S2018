defmodule Shopircruit do
  alias Shopircruit.Menus

  def menus(challenge_id) do
    Menus.retrieve_menus("/challenges.json?id=#{challenge_id}")
  end
end
