defmodule MclKanbanWeb.OwnerBoardLiveTest do
  # The owner's UI on a real store: found the crew, open a board, queue a
  # card, pin its rank, and see it in the board's columns and the drawer.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint MclKanbanWeb.Endpoint

  defp uniq, do: Integer.to_string(System.unique_integer([:positive]))

  defp node_hex(name),
    do: :crypto.hash(:sha256, "synthetic web node " <> name) |> Base.encode16(case: :lower)

  defp eventually(fun, tries \\ 100) do
    fun.() || (tries > 0 && (Process.sleep(20) || eventually(fun, tries - 1)))
  end

  test "the owner founds the crew, opens a board, queues, pins and comments" do
    {:ok, view, html} = live(build_conn(), "/")
    assert html =~ "mcl-kanban"

    agent = "web" <> uniq()

    view
    |> form("#enlist-agent", %{"name" => agent, "node_id" => node_hex(agent)})
    |> render_submit()

    assert eventually(fn -> render(view) =~ agent end)

    view |> form("#appoint-supervisor", %{"name" => agent}) |> render_submit()
    assert eventually(fn -> render(view) =~ "supervisor" end)

    repo = "example-org/web" <> uniq()
    view |> form("#open-board", %{"repo" => repo}) |> render_submit()
    assert eventually(fn -> render(view) =~ repo end)

    {:ok, board, _} = live(build_conn(), "/boards/" <> repo)

    board
    |> form("#queue-card", %{
      "issue_ref" => repo <> "#5",
      "title" => "Owner card",
      "kind" => "bug"
    })
    |> render_submit()

    assert eventually(fn -> render(board) =~ "Owner card" end)

    board |> element("[data-card-ref='#{repo}#5']") |> render_click()
    assert render(board) =~ "https://github.com/#{repo}/issues/5"

    board
    |> form("#rank-card", %{"rank" => "3", "rationale" => "Raf wants it"})
    |> render_submit()

    assert eventually(fn -> render(board) =~ "pinned" end)

    board |> form("#comment-card", %{"text" => "go for it"}) |> render_submit()
    assert eventually(fn -> render(board) =~ "go for it" end)
  end

  test "a refused owner action says why" do
    {:ok, view, _} = live(build_conn(), "/")
    view |> form("#open-board", %{"repo" => "not a repo"}) |> render_submit()
    assert render(view) =~ "invalid_repo"
  end
end
