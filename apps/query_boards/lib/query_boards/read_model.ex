defmodule QueryBoards.ReadModel do
  # How the query department reads the board read model. READ-ONLY BY API:
  # only q/2 exists. project_boards owns the file (ProjectBoards.Repo) and
  # its schema (the migrations).
  @moduledoc false

  @spec q(String.t(), list()) :: [list()]
  def q(sql, args), do: ProjectBoards.Repo.query!(sql, args).rows
end
