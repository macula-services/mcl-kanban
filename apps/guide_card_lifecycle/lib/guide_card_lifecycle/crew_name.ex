defmodule GuideCardLifecycle.CrewName do
  # What a crew's name looks like when a command names one, and the crew every
  # agent enlisted before crews existed belongs to (#28).
  #
  # A crew is a name, not an id: an operator is appointed FOR a crew, an agent
  # is enlisted INTO one, and an operator may only act on its own. The same
  # shape as an agent name, so one regex covers both and nobody has to learn
  # two rules.
  @moduledoc false

  @name ~r/^[A-Za-z][A-Za-z0-9_-]{0,39}$/
  @home "home"

  @doc """
  The crew an enlistment belongs to when it does not name one: the agents
  enlisted before #28 carry no crew in their events, and rewriting events to
  add one would be changing history to fit a later design. The projection
  reads them as this crew instead.
  """
  @spec home() :: String.t()
  def home, do: @home

  @spec name(term()) :: {:ok, String.t()} | {:error, :invalid_crew}
  def name(name) when is_binary(name), do: named(Regex.match?(@name, name), name)
  def name(_), do: {:error, :invalid_crew}

  defp named(true, name), do: {:ok, name}
  defp named(false, _name), do: {:error, :invalid_crew}
end
