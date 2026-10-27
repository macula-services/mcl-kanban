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

  # Retries fun every 20 ms, up to tries times, until it returns truthy.
  defp eventually(fun, tries \\ 150), do: fun.() || retry(fun, tries)

  defp retry(_fun, 0), do: false

  defp retry(fun, tries) do
    Process.sleep(20)
    eventually(fun, tries - 1)
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
    assert eventually(fn -> render(view) =~ ~s(<option value="#{repo}">) end)

    view
    |> form("#queue-form", %{"repo" => repo, "number" => n, "title" => title, "kind" => kind})
    |> render_submit()

    # The toast names the card at once; the ladder row lands with the next
    # coalesced reload, so wait for the row itself.
    id = IssueRef.card_id("#{repo}##{n}")
    assert eventually(fn -> has_element?(view, ~s([data-card-id="#{id}"])) end)
    id
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

  test "a second crew is enlisted as its own operator, and the rail groups by crew (#28)" do
    view = ladder()
    crew = "night" <> uniq()
    agent = "Nox" <> uniq()

    view |> element("#enlist-btn") |> render_click()

    view
    |> form("#enlist-form", %{
      "name" => agent,
      "node_id" => node_hex(agent),
      "crew" => crew,
      "role" => "operator"
    })
    |> render_submit()

    assert eventually(fn ->
             html = render(view)
             html =~ ~s(data-crew="#{crew}") and html =~ "operator #{agent}"
           end)

    assert render(view) =~ "#{agent}</b> enlisted in <b>#{crew}</b> and runs it"
  end

  test "the rail appoints a crew's operator from an agent's menu (#28)" do
    view = ladder()
    agent = "Op" <> uniq()
    button = ~s(button[phx-value-role="operator"][phx-value-name="#{agent}"])

    view |> element("#enlist-btn") |> render_click()

    view
    |> form("#enlist-form", %{"name" => agent, "node_id" => node_hex(agent)})
    |> render_submit()

    assert eventually(fn -> has_element?(view, button) end)
    view |> element(button) |> render_click()

    assert eventually(fn -> render(view) =~ "operator #{agent}" end)
    refute has_element?(view, button)
  end

  test "the appointment's reply names the crew, not the key it is acted on by (#40)" do
    # The rail sends the crew's KEY to act on and the NAME to read. The reply
    # read "crew_name", which is never a parameter name: phx-value-crew-name
    # arrives as "crew-name", so a realm crew's 64-hex key was printed where
    # the crew's name belongs.
    view = ladder()
    crew = node_hex("realm crew " <> uniq())
    name = "RealmCrew" <> uniq()
    agent = "Rk" <> uniq()

    # The fact the realm sends when it admits a crew: its projection is what
    # gives a realm crew a name a person reads, keyed by the id the board acts
    # on. This is the only way a crew's name and its key differ.
    realm_crew_fact(crew, name)

    view |> element("#enlist-btn") |> render_click()

    view
    |> form("#enlist-form", %{
      "name" => agent,
      "node_id" => node_hex(agent),
      "crew" => crew,
      "role" => "agent"
    })
    |> render_submit()

    assert eventually(fn -> render(view) =~ "enlisted" end)

    button =
      ~s(button[phx-value-role="operator"][phx-value-name="#{agent}"][phx-value-crew="#{crew}"])

    assert eventually(fn -> has_element?(view, button) end)
    html = view |> element(button) |> render_click()

    assert html =~ "runs the <b>#{name}</b> crew"
    refute html =~ "runs the <b>#{crew}</b> crew"
  end

  # One crew fact, delivered exactly as the mesh's projector takes it: the
  # crew id the board acts on, and the name the realm admitted it under.
  defp realm_crew_fact(crew_id, crew_name) do
    type = "crew_fact_observed_v1"

    [module] =
      Enum.filter(
        ProjectBoards.Application.projections(),
        &(type in &1.interested_in())
      )

    data = %{event_type: type, crew_id: crew_id, crew_name: crew_name}
    envelope = %{event_type: type, event_id: "evt-" <> uniq(), version: 0, data: data}

    assert {:ok, _} = module.handle_event(type, envelope, %{version: 0}, %{})

    on_exit(fn ->
      ProjectBoards.ReadModel.write([
        {"DELETE FROM crews WHERE name = ?", [crew_id]},
        {"DELETE FROM crew_names WHERE crew_id = ?", [crew_id]}
      ])
    end)
  end

  test "the board dialogs take a realm crew's key, as the enlist dialog does (#40)" do
    view = ladder()
    view |> element("#open-board-btn") |> render_click()
    assert has_element?(view, ~s(#ob-crew[pattern="[A-Za-z][A-Za-z0-9_-]{0,39}|[0-9a-f]{64}"]))

    view |> element("#close_dialog, button[phx-click='close_dialog']") |> render_click()
    view |> element("#open-board-btn") |> render_click()
    view |> element("#hand-over-btn") |> render_click()

    assert has_element?(
             view,
             ~s(#ho-crew[pattern="[A-Za-z][A-Za-z0-9_-]{0,39}|[0-9a-f]{64}"])
           )
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

  test "the owner opens a board for a crew, then hands it over to another (#29)" do
    view = ladder()
    repo = "example-org/crewboard" <> uniq()

    view |> element("#open-board-btn") |> render_click()
    view |> form("#open-board-form", %{"repo" => repo, "crew" => "night"}) |> render_submit()
    assert eventually(fn -> crew_of(repo) == "night" end)

    view |> element("#open-board-btn") |> render_click()
    view |> element("#hand-over-btn") |> render_click()
    view |> form("#hand-over-form", %{"repo" => repo, "crew" => "home"}) |> render_submit()

    assert render(view) =~ "handed over to <b>home</b>"
    assert eventually(fn -> crew_of(repo) == "home" end)

    view |> element("#open-board-btn") |> render_click()
    view |> element("#hand-over-btn") |> render_click()
    view |> form("#hand-over-form", %{"repo" => repo, "crew" => "home"}) |> render_submit()
    assert render(view) =~ "already_home_crew"
  end

  defp crew_of(repo) do
    Enum.find_value(
      QueryBoards.GetBoards.GetBoards.get_boards(),
      &(&1.repo == repo && &1.home_crew)
    )
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

    assert eventually(fn -> has_element?(view, ~s(section[data-key="#{pkg}"])) end)
    html = render(view)
    assert html =~ "Ship the ladder"
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

    # The toast names the agent at once; the lane picker lists it with the
    # next coalesced reload, so wait for the option itself.
    assert eventually(fn -> has_element?(view, ~s(#reserve-form option[value="#{agent}"])) end)

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

  test "a dialog keeps its open attribute across server patches, so typing never closes it" do
    view = ladder()

    for {button, dialog} <- [
          {"#enlist-btn", "enlist"},
          {"#open-board-btn", "open-board"},
          {"#queue-btn", "queue"}
        ] do
      view |> element(button) |> render_click()

      [mounted] =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("dialog##{dialog}")
        |> LazyHTML.attribute("phx-mounted")

      assert mounted =~ "ignore_attrs" and mounted =~ "open", dialog
      view |> render_hook("close_dialog", %{})
    end

    view |> element("#enlist-btn") |> render_click()
    view |> form("#enlist-form", %{"name" => "Typing", "node_id" => "ab"}) |> render_change()
    assert has_element?(view, "dialog#enlist")

    # What the owner typed survives any later render (a board change, a hint),
    # not only while its field has focus.
    send(view.pid, {:boards_changed, %{}})
    assert has_element?(view, ~s(#e-name[value="Typing"]))
    assert has_element?(view, ~s(#e-node[value="ab"]))

    view |> render_hook("close_dialog", %{})
    view |> element("#open-board-btn") |> render_click()
    view |> form("#open-board-form", %{"repo" => "example-org/half"}) |> render_change()
    send(view.pid, {:boards_changed, %{}})
    assert has_element?(view, ~s(#ob-repo[value="example-org/half"]))
  end

  # Counts the read model queries the view's own process runs while fun runs.
  defp view_queries(view, fun) do
    counter = :counters.new(1, [])
    pid = view.pid
    handler = "view-queries-" <> uniq()

    :ok =
      :telemetry.attach(
        handler,
        [:project_boards, :repo, :query],
        fn _event, _measurements, _meta, _config ->
          if self() == pid, do: :counters.add(counter, 1, 1)
        end,
        nil
      )

    fun.()
    :telemetry.detach(handler)
    :counters.get(counter, 1)
  end

  test "a burst of board changes reloads the ladder once, not once per change" do
    view = ladder()
    render(view)

    one =
      view_queries(view, fn ->
        send(view.pid, {:boards_changed, %{}})
        Process.sleep(600)
        render(view)
      end)

    assert one > 0

    burst =
      view_queries(view, fn ->
        for _ <- 1..20, do: send(view.pid, {:boards_changed, %{}})
        Process.sleep(600)
        render(view)
      end)

    assert burst <= 2 * one, "#{burst} queries for 20 changes, #{one} for one"
  end

  test "the owner pauses a package and a repo with a reason and resumes them; a card is deferred from its drawer (#17)" do
    view = ladder()
    repo = "example-org/pause" <> uniq()
    open_board(view, repo)
    id = queue(view, repo, 1, "Pause me")
    pkg = "#{repo}#70"
    owner(OpenPackageV1, MaybeOpenPackage, %{issue_ref: pkg, title: "Later"})
    owner(FileCardV1, MaybeFileCard, %{card_id: id, package_ref: pkg})
    assert eventually(fn -> has_element?(view, ~s([data-pause="#{pkg}"])) end)

    view |> element(~s([data-pause="#{pkg}"])) |> render_click()
    view |> form("#pause-form", %{"reason" => "after the demo"}) |> render_submit()
    assert eventually(fn -> has_element?(view, ~s([data-resume="#{pkg}"])) end)
    assert render(view) =~ "paused"

    view |> element(~s([data-resume="#{pkg}"])) |> render_click()
    assert eventually(fn -> has_element?(view, ~s([data-pause="#{pkg}"])) end)

    by_repo = ladder("/?" <> URI.encode_query(%{"view" => "repo", "focus" => repo}))
    by_repo |> element(~s([data-pause="#{repo}"])) |> render_click()
    by_repo |> form("#pause-form", %{"reason" => "not now"}) |> render_submit()
    assert eventually(fn -> has_element?(by_repo, ~s([data-resume="#{repo}"])) end)
    by_repo |> element(~s([data-resume="#{repo}"])) |> render_click()
    assert eventually(fn -> has_element?(by_repo, ~s([data-pause="#{repo}"])) end)

    drawer = ladder("/?" <> URI.encode_query(%{"card" => id}))
    drawer |> element(~s(#drawer [phx-value-action="defer"])) |> render_click()

    drawer
    |> form("#reason-form", %{"action" => "defer", "reason" => "not this week"})
    |> render_submit()

    assert eventually(fn ->
             match?({:ok, %{state: "deferred"}}, GetCardById.get_card_by_id(id))
           end)

    assert eventually(fn -> has_element?(drawer, ~s(#drawer [phx-click="resume"])) end)
    drawer |> element(~s(#drawer [phx-click="resume"])) |> render_click()
    assert eventually(fn -> match?({:ok, %{state: "queued"}}, GetCardById.get_card_by_id(id)) end)
  end

  test "the owner adopts the crew's goal from the ladder; the banner shows it and when it was set (#18)" do
    view = ladder()
    repo = "example-org/goalui" <> uniq()
    open_board(view, repo)
    pkg = "#{repo}#80"
    owner(OpenPackageV1, MaybeOpenPackage, %{issue_ref: pkg, title: "Ship the goal"})
    assert eventually(fn -> has_element?(view, ~s(section[data-key="#{pkg}"])) end)

    view |> element("#goal-btn") |> render_click()

    view
    |> form("#goal-form", %{"goal" => "So the crew pulls its own work", "packages" => [pkg]})
    |> render_submit()

    assert eventually(fn -> render(view) =~ "So the crew pulls its own work" end)
    assert has_element?(view, "#goal [data-goal-package=\"#{pkg}\"]")
    assert render(view) =~ "set by owner"
  end
end
