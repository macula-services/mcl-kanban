defmodule ProjectBoards.Release do
  # Release tasks: run the read model's migrations before the app boots.
  #
  #   bin/migrate   ./mcl_kanban eval ProjectBoards.Release.migrate
  #   bin/start     migrate, then start the release
  #
  # A rollback is ./mcl_kanban eval 'ProjectBoards.Release.rollback(20261006000002)'.
  @moduledoc false

  @app :project_boards

  def migrate do
    Application.load(@app)

    for repo <- repos() do
      :ok = ensure_storage(repo)
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  def rollback(version) do
    Application.load(@app)

    for repo <- repos(),
        do:
          {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))

    :ok
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp ensure_storage(repo) do
    case repo.__adapter__().storage_up(repo.config()) do
      :ok -> :ok
      {:error, :already_up} -> :ok
    end
  end
end
