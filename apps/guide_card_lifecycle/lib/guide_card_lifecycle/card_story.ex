defmodule GuideCardLifecycle.CardStory do
  # The optional story beside a card's title: "As a {role} I want {ask} so
  # that {value}". All three parts, or none.
  @moduledoc false

  @max 300

  @spec story(term()) :: {:ok, map() | nil} | {:error, :invalid_story}
  def story(nil), do: {:ok, nil}

  def story(%{role: role, ask: ask, value: value}) do
    with {:ok, role} <- part(role),
         {:ok, ask} <- part(ask),
         {:ok, value} <- part(value),
         do: {:ok, %{role: role, ask: ask, value: value}}
  end

  def story(_), do: {:error, :invalid_story}

  defp part(text), do: GuideCardLifecycle.CardText.required(text, @max, :invalid_story)

  @spec sentence(map() | nil) :: String.t() | nil
  def sentence(nil), do: nil
  def sentence(%{role: r, ask: a, value: v}), do: "As a #{r} I want #{a} so that #{v}"
end
