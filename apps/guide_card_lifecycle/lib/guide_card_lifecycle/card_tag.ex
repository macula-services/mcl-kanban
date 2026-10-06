defmodule GuideCardLifecycle.CardTag do
  # A free-form tag: trimmed, 1 to 40 characters. A card holds a tag once.
  @moduledoc false

  @spec tag(term()) :: {:ok, String.t()} | {:error, :invalid_tag}
  def tag(tag), do: GuideCardLifecycle.CardText.required(tag, 40, :invalid_tag)

  @spec tags(term()) :: {:ok, [String.t()]} | {:error, :invalid_tag}
  def tags(nil), do: {:ok, []}

  def tags(tags) when is_list(tags) and length(tags) <= 20 do
    tags
    |> Enum.reduce_while({:ok, []}, fn t, {:ok, acc} -> collected(tag(t), acc) end)
    |> then(fn
      {:ok, acc} -> {:ok, acc |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end)
  end

  def tags(_), do: {:error, :invalid_tag}

  defp collected({:ok, t}, acc), do: {:cont, {:ok, [t | acc]}}
  defp collected(error, _acc), do: {:halt, error}
end
