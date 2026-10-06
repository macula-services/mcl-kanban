defmodule ProjectBoards.Repo do
  # The board read model: one sqlite file under MCL_DATA_DIR. Its schema lives
  # in priv/repo/migrations and nowhere else; bin/start runs them before the
  # release boots (ProjectBoards.Release). The projections write through
  # ProjectBoards.ReadModel; the query department reads through
  # QueryBoards.ReadModel.
  @moduledoc false

  use Ecto.Repo, otp_app: :project_boards, adapter: Ecto.Adapters.SQLite3
end
