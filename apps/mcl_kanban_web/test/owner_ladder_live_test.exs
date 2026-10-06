defmodule MclKanbanWeb.OwnerLadderLiveTest do
  # The owner's ladder on a real store: dialogs instead of raw forms, packages
  # in rank order with their cards, a drag that re-ranks and pins with one
  # owner rank, toasts that say what to do about a refusal, and the view,
  # focus, filter and search in the URL.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.FileCard.{FileCardV1, MaybeFileCard}
  alias GuideCardLifecycle.IssueRef
  alias GuideCardLifecycle.OpenPackage.{MaybeOpenPackage, OpenPackageV1}
  alias QueryBoards.GetCardById.GetCardById

  @endpoint MclKanbanWeb.Endpoint

  defp uniq, do: Integer.to_string(System.unique_integer([:positive]))

  defp node_hex(name),
    do: :crypto.hash(:sha256, "synthetic ladder node " <> name) |> Base.encode16(case: :lower)

  defp eventually(fun, tries \\ 150) do
    fun.() || (tries > 0 && (Process.sleep(20) || eventually(fun, tries - 1)))
  end

  defp ladder(path \\ "/") do
    {:ok, view, _html} = live(build_conn(), path)
    view
  end

  defp open_board(view, repo) do
    view |> element("#open-board-btn") |> render_click()
    view |> form("#open-board-form", %{"repo" => repo}) |> render_submit()
    assert eventually(fn -> render(view) =~ repo end)
  end

  defp queue(view, repo, n, title, kind \\ "slice") do
    view |> element("#queue-btn") |> render_click()

    view
    |> form("#queue-form", %{"repo" => repo, "number" => n, "title" => title, "kind" => kind})
    |> render_submit()

    assert eventually(fn -> render(view) =~ title end)
    IssueRef.card_id("#{repo}##{n}")
  end

  defp owner(command, desk, args) do
    {:ok, cmd} = command.new(Map.put(args, :by, Actor.owner()))
    {:ok, _, _} = desk.dispatch(cmd)
  end

  defp rank_of(card_id) do
    {:ok, card} = GetCardById.get_card_by_id(card_id)
    {card.rank, card.pinned, card.work_package}
  end

  test "enlist through the dialog, with live hints, and appoint in the same step" do
    view = ladder()
    agent = "Ag" <> uniq()

    view |> element("#enlist-btn") |> render_click()
    assert render(view) =~ "Waiting for a node id"

    html = view |> form("#enlist-form", %{"name" => agent, "node_id" => "abc"}) |> render_change()
    assert html =~ "3 of 64 hex characters"

    view
    |> form("#enlist-form", %{
      "name" => agent,
      "node_id" => node_hex(agent),
      "role" => "prioritiser"
    })
    |> render_submit()

    assert eventually(fn ->
             html = render(view)
             html =~ agent and html =~ "prioritiser"
           end)

    assert render(view) =~ "#{agent}</b> enlisted"
  end

  test "open a board and queue a card through dialogs; a duplicate says why and what to do" do
    view = ladder()
    repo = "example-org/ladder" <> uniq()
    open_board(view, repo)
    queue(view, repo, 3, "Draw the ladder", "ui")

    view |> element("#queue-btn") |> render_click()

    view
    |> form("#queue-form", %{"repo" => repo, "number" => "3", "title" => "Again", "kind" => "bug"})
    |> render_submit()

    html = render(view)
    assert html =~ "already_on_board"
    assert html =~ "That issue already has a card"
  end

  test "packages lead the ladder with their cards; the repo view cuts the same cards by repo" do
    view = ladder()
    repo = "example-org/pkgs" <> uniq()
    open_board(view, repo)
    card = queue(view, repo, 1, "Inside the package")
    loose = queue(view, repo, 2, "Not in a package")

    pkg = "#{repo}#50"
    owner(OpenPackageV1, MaybeOpenPackage, %{issue_ref: pkg, title: "Ship the ladder"})
    owner(FileCardV1, MaybeFileCard, %{card_id: card, package_ref: pkg})

    assert eventually(fn -> render(view) =~ "Ship the ladder" end)
    html = render(view)
    assert html =~ ~s(data-key="#{pkg}")
    assert html =~ "Not in a package"

    focused = ladder("/?" <> URI.encode_query(%{"view" => "pkg", "focus" => pkg}))
    html = render(focused)
    assert html =~ "Inside the package"
    refute html =~ ~s(data-card-id="#{loose}")

    by_repo = ladder("/?" <> URI.encode_query(%{"view" => "repo", "focus" => repo}))
    html = render(by_repo)
    assert html =~ "Inside the package"
    assert html =~ "Not in a package"
    assert html =~ "in ##{50}"
  end

  test "a drag re-ranks with one owner rank, pins, files into the target package, and undoes" do
    view = ladder()
    repo = "example-org/drag" <> uniq()
    open_board(view, repo)
    a = queue(view, repo, 1, "Card A")
    b = queue(view, repo, 2, "Card B")
    view |> render_hook("pin_at", %{"card_id" => a, "rank" => "10"})
    view |> render_hook("pin_at", %{"card_id" => b, "rank" => "20"})
    assert eventually(fn -> rank_of(b) == {20, 1, nil} end)

    pkg = "#{repo}#60"
    owner(OpenPackageV1, MaybeOpenPackage, %{issue_ref: pkg, title: "Target package"})

    moving = queue(view, repo, 3, "Card C")

    view
    |> render_hook("rerank", %{
      "card_id" => moving,
      "after_card_id" => a,
      "before_card_id" => b,
      "group" => pkg,
      "view" => "pkg"
    })

    assert eventually(fn -> rank_of(moving) == {15, 1, pkg} end)
    assert render(view) =~ "rank 15, pinned"
    assert render(view) =~ "Moved into"

    view |> element("[data-undo]") |> render_click()
    assert eventually(fn -> elem(rank_of(moving), 2) == nil end)
  end

  test "below an unranked card is refused, with the fix" do
    view = ladder()
    repo = "example-org/unranked" <> uniq()
    open_board(view, repo)
    a = queue(view, repo, 1, "Unranked A")
    b = queue(view, repo, 2, "Unranked B")

    view
    |> render_hook("rerank", %{
      "card_id" => b,
      "after_card_id" => a,
      "before_card_id" => nil,
      "group" => "loose",
      "view" => "pkg"
    })

    html = render(view)
    assert html =~ "cannot go below an unranked card"
    assert html =~ "Rank the card above it first"
  end

  test "p pins a ranked card at its rank and unpins it; an unranked card says how to rank it" do
    view = ladder()
    repo = "example-org/pin" <> uniq()
    open_board(view, repo)
    id = queue(view, repo, 1, "Pin me")

    view |> render_hook("pin", %{"card_id" => id})
    assert render(view) =~ "is unranked"

    view |> render_hook("pin_at", %{"card_id" => id, "rank" => "4"})
    assert eventually(fn -> rank_of(id) == {4, 1, nil} end)
    view |> render_hook("pin", %{"card_id" => id})
    assert eventually(fn -> rank_of(id) == {4, 0, nil} end)
    assert render(view) =~ "unpinned"
  end

  test "the drawer opens on ?card=, comments as the owner, and the crew rail reserves and discharges" do
    view = ladder()
    repo = "example-org/drawer" <> uniq()
    open_board(view, repo)
    id = queue(view, repo, 7, "Open me")

    view |> element(~s([data-card-id="#{id}"] .body)) |> render_click()
    assert_patch(view, "/?" <> URI.encode_query(%{"card" => id}))
    assert render(view) =~ "https://github.com/#{repo}/issues/7"

    view |> form("#comment-form", %{"text" => "go for it"}) |> render_submit()
    assert eventually(fn -> render(view) =~ "go for it" end)

    agent = "Rail" <> uniq()
    view |> element("#enlist-btn") |> render_click()

    view
    |> form("#enlist-form", %{"name" => agent, "node_id" => node_hex(agent), "role" => "agent"})
    |> render_submit()

    assert eventually(fn -> render(view) =~ agent end)

    view |> form("#reserve-form", %{"lane" => agent}) |> render_change()
    assert eventually(fn -> render(view) =~ "reserved for <b>#{agent}</b>" end)

    view |> element(~s([data-discharge="#{agent}"])) |> render_click()
    assert eventually(fn -> render(view) =~ "#{agent}</b> discharged" end)
  end

  test "filters and search live in the URL, with empty states that say how to get back" do
    view = ladder("/?filter=blocked&q=zzzz-nothing-" <> uniq())
    assert render(view) =~ "No card matches"

    view = ladder("/?view=repo&focus=example-org/none" <> uniq())
    assert render(view) =~ "example-org/none"
  end
end
