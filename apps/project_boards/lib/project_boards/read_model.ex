defmodule ProjectBoards.ReadModel do
  # How the projections write the board read model: each projection's
  # statements in one transaction through ProjectBoards.Repo, all or none.
  # The schema is the migrations' (priv/repo/migrations), never this module's.
  @moduledoc false

  alias ProjectBoards.Repo

  @doc "Runs the statements in one transaction."
  @spec write([{String.t(), list()}]) :: :ok | {:error, term()}
  def write(statements) do
    case Repo.transaction(fn -> Enum.each(statements, &run/1) end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The rows a query returns, for the projections' own tests and checks."
  @spec q(String.t(), list()) :: [list()]
  def q(sql, args), do: Repo.query!(sql, args).rows

  defp run({sql, args}) do
    case Repo.query(sql, args) do
      {:ok, _} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end
end
