defmodule QueryBoards.GetGoal.GetGoal do
  # get_goal: the crew's one goal (#18), the sentence, its packages, who
  # adopted it and when; nil before one is adopted.
  @moduledoc false

  alias QueryBoards.ReadModel

  @spec get_goal() :: map() | nil
  def get_goal do
    "SELECT goal, adopted_by, adopted_at FROM crew_goal WHERE id = 1"
    |> ReadModel.q([])
    |> goal()
  end

  @doc """
  Waits (bounded) until the read model holds the goal adopted at `at`, so
  adopt_goal replies only once the next read sees it.
  """
  @spec await_adopted(integer(), pos_integer()) :: :ok | {:error, :read_model_behind}
  def await_adopted(at, timeout_ms \\ 5_000),
    do: ReadModel.await("SELECT adopted_at FROM crew_goal WHERE id = 1", [], [[at]], timeout_ms)

  defp goal([[goal, by, at]]) do
    packages =
      "SELECT ref FROM crew_goal_packages ORDER BY ref" |> ReadModel.q([]) |> Enum.map(&hd/1)

    %{goal: goal, packages: packages, by: by, at: at}
  end

  defp goal([]), do: nil
end
