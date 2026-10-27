defmodule GuideCardLifecycle.CrewName do
  # What a crew's name looks like, what a crew's KEY looks like, and the crew
  # every agent enlisted before crews existed belongs to (#28).
  #
  # A crew is acted on by its KEY (#40): an operator is appointed FOR one, an
  # agent is enlisted INTO one, and an operator may only act on its own. For a
  # crew the realm admitted the key is its `crew_id`; for a crew the board's
  # own owner made it is the name, exactly as before. A name and an id cannot
  # collide, so one field carries both.
  #
  # A name is the same shape as an agent name, so one regex covers both and
  # nobody has to learn two rules.
  @moduledoc false

  @name ~r/^[A-Za-z][A-Za-z0-9_-]{0,39}$/
  @key ~r/\A[0-9a-f]{64}\z/
  @home "home"

  @doc """
  The crew an enlistment belongs to when it does not name one: the agents
  enlisted before #28 carry no crew in their events, and rewriting events to
  add one would be changing history to fit a later design. The projection
  reads them as this crew instead.
  """
  @spec home() :: String.t()
  def home, do: @home

  @doc """
  The home crew an event names (#29): a board, card or package from before
  #29 names none, and belongs to the first crew, for the reason home/0 gives.
  """
  @spec home_crew_in(map()) :: String.t()
  def home_crew_in(%{home_crew: crew}) when is_binary(crew), do: crew
  def home_crew_in(_event), do: @home

  @spec name(term()) :: {:ok, String.t()} | {:error, :invalid_crew}
  def name(name) when is_binary(name), do: named(Regex.match?(@name, name), name)
  def name(_), do: {:error, :invalid_crew}

  @doc """
  The KEY a crew is acted on by (#40 option b): its `crew_id` (64 lowercase
  hex) for a crew the realm admitted, its name for a crew the board's own
  owner made. One field, no prefix, because the two shapes cannot collide --
  a name is at most 40 characters and the id is always 64 -- so an id is
  never read as a name and a name is never read as an id.
  """
  @spec key(term()) :: {:ok, String.t()} | {:error, :invalid_crew}
  def key(key) when is_binary(key) do
    named(Regex.match?(@key, key) or Regex.match?(@name, key), key)
  end

  def key(_), do: {:error, :invalid_crew}

  defp named(true, name), do: {:ok, name}
  defp named(false, _name), do: {:error, :invalid_crew}
end
