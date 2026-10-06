defmodule GuideCardLifecycle.CardText do
  # The text a card command carries: trimmed, non-empty when required, and
  # bounded, so one call cannot write a megabyte into the board.
  @moduledoc false

  @spec required(term(), pos_integer(), atom()) :: {:ok, String.t()} | {:error, atom()}
  def required(text, max, error) when is_binary(text), do: bounded(String.trim(text), max, error)
  def required(_text, _max, error), do: {:error, error}

  @spec optional(term(), pos_integer(), atom()) :: {:ok, String.t()} | {:error, atom()}
  def optional(nil, _max, _error), do: {:ok, ""}
  def optional(text, max, error) when is_binary(text), do: within(String.trim(text), max, error)
  def optional(_text, _max, error), do: {:error, error}

  defp bounded("", _max, error), do: {:error, error}
  defp bounded(text, max, error), do: within(text, max, error)

  defp within(text, max, error), do: fits(String.length(text) <= max, text, error)

  defp fits(true, text, _error), do: {:ok, text}
  defp fits(false, _text, error), do: {:error, error}
end
