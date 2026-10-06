defmodule GuideCardLifecycle.CardKind do
  # A card's kind gives its colour, in Jira's colours: bug red, slice green,
  # ui blue. Tags never change the colour.
  @moduledoc false

  @colours %{"bug" => "#e5493a", "slice" => "#63ba3c", "ui" => "#4bade8"}

  @spec kinds() :: [String.t()]
  def kinds, do: ["bug", "slice", "ui"]

  @spec kind(term()) :: {:ok, String.t()} | {:error, :invalid_kind}
  def kind(kind) when is_map_key(@colours, kind), do: {:ok, kind}
  def kind(_), do: {:error, :invalid_kind}

  @spec colour(String.t()) :: String.t()
  def colour(kind), do: Map.fetch!(@colours, kind)
end
