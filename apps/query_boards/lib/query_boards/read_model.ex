defmodule QueryBoards.ReadModel do
  # How the query department reads the board read model. READ-ONLY BY API:
  # q/2, and await/4 which polls a q/2 until it shows a write. project_boards owns the file (ProjectBoards.Repo) and
  # its schema (the migrations).
  @moduledoc false

  @spec q(String.t(), list()) :: [list()]
  def q(sql, args), do: ProjectBoards.Repo.query!(sql, args).rows

  @doc """
  Polls the query every 15 ms until its rows are the expected ones, or the
  timeout runs out: a command's reply waits for the read model to hold its
  own write, so the caller's next read sees it.
  """
  @spec await(String.t(), list(), [list()], pos_integer()) :: :ok | {:error, :read_model_behind}
  def await(sql, args, expected, timeout_ms),
    do: poll(sql, args, expected, System.monotonic_time(:millisecond) + timeout_ms)

  defp poll(sql, args, expected, deadline),
    do: polled(q(sql, args) == expected, sql, args, expected, deadline)

  defp polled(true, _sql, _args, _expected, _deadline), do: :ok

  defp polled(false, sql, args, expected, deadline),
    do: retry(System.monotonic_time(:millisecond) >= deadline, sql, args, expected, deadline)

  defp retry(true, _sql, _args, _expected, _deadline), do: {:error, :read_model_behind}

  defp retry(false, sql, args, expected, deadline) do
    Process.sleep(15)
    poll(sql, args, expected, deadline)
  end
end
