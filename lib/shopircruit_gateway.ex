# interface for challenge-related API requests
defmodule Shopircruit.Gateway do
  use HTTPoison.Base

  @endpoint "https://backend-challenge-summer-2018.herokuapp.com"

  def endpoint do
    @endpoint
  end

  defp process_url(url) do
    case url |> String.slice(0, 8) |> String.downcase do
      "http://" <> _ -> super url
      "https://" <> _ -> super url
      _ -> @endpoint <> url
    end
  end
end
