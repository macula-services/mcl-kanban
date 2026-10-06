defmodule ProjectBoards.ReadModelMigrationsTest do
  # A new release opens the read model an older release wrote, through its
  # migrations, and keeps every row (#10). The fixtures are the schemas
  # v0.1.0 and v0.2.0 created from code, before the read model had
  # migrations, extracted from those tags (v0.2.1 changed no schema; the live
  # board holds its file).
  use ExUnit.Case, async: false

  alias ProjectBoards.Repo

  @fixtures Path.expand("fixtures", __DIR__)

  defp file_from(version) do
    path =
      Path.join(
        System.tmp_dir!(),
        "kanban_#{version}_#{System.unique_integer([:positive])}.sqlite3"
      )

    {:ok, pid} = Repo.start_link(name: nil, database: path, pool_size: 1)
    Repo.put_dynamic_repo(pid)

    @fixtures
    |> Path.join("read_model_#{version}.sql")
    |> File.read!()
    |> String.split(";", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.each(&Repo.query!/1)

    Repo.query!(
      "INSERT INTO cards (card_id, issue_ref, repo, board_id, title, kind, status, version) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      [
        "card-old",
        "example-org/widget#1",
        "example-org/widget",
        "board-old",
        "Kept",
        "slice",
        1,
        3
      ]
    )

    on_exit(fn -> File.rm(path) end)
    pid
  end

  defp migrate(pid) do
    Ecto.Migrator.run(Repo, :up, all: true, dynamic_repo: pid, log: false)
  end

  defp columns(table) do
    Repo.query!("SELECT name FROM pragma_table_info('#{table}')").rows |> List.flatten()
  end

  for version <- ["v0.1.0", "v0.2.0", "v0.2.1"] do
    test "a read model written by #{version} migrates and keeps its rows" do
      pid = file_from(unquote(version))
      assert [_ | _] = migrate(pid)

      assert ~w(ranked_at work_package package_rank package_card) -- columns("cards") == []
      assert "issue_ref" in columns("packages")

      assert [["card-old", "Kept", 3, nil]] =
               Repo.query!("SELECT card_id, title, version, work_package FROM cards").rows

      # A second boot finds nothing left to run.
      assert [] = migrate(pid)
    end
  end

  test "a fresh file gets the whole schema" do
    path =
      Path.join(System.tmp_dir!(), "kanban_fresh_#{System.unique_integer([:positive])}.sqlite3")

    {:ok, pid} = Repo.start_link(name: nil, database: path, pool_size: 1)
    Repo.put_dynamic_repo(pid)
    on_exit(fn -> File.rm(path) end)

    assert [_, _, _] = migrate(pid)

    for table <- ~w(boards cards card_tags card_links card_comments crew packages) do
      assert columns(table) != [], table
    end
  end

  test "a v0.2.x card already filed into its own package is marked as its header (#15)" do
    pid = file_from("v0.2.1")

    Repo.query!(
      "INSERT INTO cards (card_id, issue_ref, repo, board_id, title, kind, status, version, work_package) " <>
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
      ["card-head", "example-org/widget#2", "example-org/widget", "board-old", "Head", "slice", 1, 2,
       "example-org/widget#2"]
    )

    migrate(pid)

    assert [["card-head", 1], ["card-old", 0]] =
             Repo.query!("SELECT card_id, package_card FROM cards ORDER BY card_id").rows
  end
end
