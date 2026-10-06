defmodule MclKanbanWeb.LadderComponents do
  # The pieces of the owner's ladder, as the approved mock draws them
  # (docs/design/owner-ui-v2-mock.html): the top bar, the boards nav, the
  # ladder of groups and cards, the crew rail, the card drawer, the dialogs
  # and the toasts. Colour comes from a card's kind, on the stripe and the
  # kind word only.
  @moduledoc false

  use Phoenix.Component

  alias GuideCardLifecycle.CardKind
  alias GuideCardLifecycle.CardStory
  alias GuideCardLifecycle.IssueRef
  alias Phoenix.LiveView.JS

  @avatars ~w(#2E7D6B #6B4FBB #B8732A #B23A3A #3A6FB2 #8A6D2F #5B6470 #2F7F9A)

  # ---------- small helpers ----------

  def esc(nil), do: ""
  def esc(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  def short_ref(ref) do
    [repo, n] = String.split(ref, "#")
    short_repo(repo) <> " #" <> n
  end

  def short_repo(repo), do: repo |> String.split("/") |> List.last()
  def num(ref), do: "#" <> (ref |> String.split("#") |> List.last())
  def avatar(name), do: Enum.at(@avatars, :erlang.phash2(name, length(@avatars)))
  def initial(name), do: String.first(name)

  def kind_var("bug"), do: "var(--bug)"
  def kind_var("ui"), do: "var(--ui)"
  def kind_var(_slice), do: "var(--slice)"

  defp counts(cards) do
    Enum.reduce(cards, %{q: 0, c: 0, b: 0, d: 0}, fn c, acc ->
      Map.update!(acc, count_key(c.state), &(&1 + 1))
    end)
  end

  defp count_key("claimed"), do: :c
  defp count_key("blocked"), do: :b
  defp count_key("finished"), do: :d
  defp count_key(_queued), do: :q

  defp open_n(cn), do: cn.q + cn.c + cn.b

  defp since(nil, _now), do: ""

  defp since(at, now) do
    minutes = div(max(now - at, 0), 60_000)

    cond do
      minutes < 60 -> "#{max(minutes, 1)}m"
      minutes < 1440 -> "#{div(minutes, 60)}h"
      true -> "#{div(minutes, 1440)}d"
    end
  end

  defp at(ms), do: ms |> DateTime.from_unix!(:millisecond) |> Calendar.strftime("%Y-%m-%d %H:%M")

  defp nav_href(view, focus), do: "/?" <> URI.encode_query(%{"view" => view, "focus" => focus})

  defp blocker(card, by_id) do
    Enum.find_value(card.linked_from, fn
      %{link: "blocks", from_card_id: from} -> Map.get(by_id, from)
      _ -> nil
    end)
  end

  # ---------- the page ----------

  def ladder_page(assigns) do
    ~H"""
    <div id="keys" phx-hook="Keys" data-view={@nav["view"]}>
      <.top_bar nav={@nav} cards={@cards} />
      <div class="shell">
        <.boards_nav nav={@nav} packages={@packages} cards={@cards} />
        <main class="main" id="main">
          <div class="main-head">
            <h1>{heading(@nav, @packages)}</h1>
            <p>{subheading(@nav)}</p>
            <button type="button" id="queue-btn" class="btn sm" phx-click="open_dialog" phx-value-dialog="queue">
              Queue a card <kbd>n</kbd>
            </button>
          </div>
          <div id="ladder" phx-hook="Ladder" data-view={@nav["view"]}>
            <.group
              :for={g <- @groups}
              group={g}
              open={not MapSet.member?(@collapsed, g.key)}
              view={@nav["view"]}
              selected={@selected}
              by_id={@by_id}
              now={@now}
            />
            <.empty :if={@groups == [] or Enum.all?(@groups, &(&1.cards == [] and &1.kind != :package))} nav={@nav} boards={@boards} />
          </div>
        </main>
        <.crew_rail crew={@crew} now={@now} />
      </div>
      <.drawer card={@card} by_id={@by_id} crew={@crew} packages={@packages} />
      <div class="toasts" id="toasts" aria-live="polite">
        <.toast :for={t <- @toasts} toast={t} />
      </div>
      <.dialogs dialog={@dialog} enlist={@enlist} values={@values} boards={@boards} card={@card} cards={@cards} crew={@crew} />
    </div>
    """
  end

  defp heading(%{"view" => "pkg", "focus" => "all"}, _packages),
    do: "Every package, in rank order"

  defp heading(%{"view" => "pkg", "focus" => "loose"}, _packages), do: "Cards not in a package"

  defp heading(%{"view" => "pkg", "focus" => ref}, packages),
    do: Enum.find_value(packages, ref, &(&1.issue_ref == ref && &1.title))

  defp heading(%{"focus" => "all"}, _packages), do: "Every repo"
  defp heading(%{"focus" => repo}, _packages), do: repo

  defp subheading(%{"view" => "pkg", "focus" => "all"}),
    do: "The prioritiser ranks packages first, then the cards inside. Your drag pins."

  defp subheading(%{"view" => "repo", "focus" => "all"}),
    do: "One board per repo. The same cards, cut the other way."

  defp subheading(_nav), do: ""

  # ---------- top bar ----------

  attr(:nav, :map, required: true)
  attr(:cards, :list, required: true)

  def top_bar(assigns) do
    ~H"""
    <header class="top">
      <a class="brand" href="/" aria-label="mcl-kanban, crew board">
        <svg viewBox="0 0 20 20" aria-hidden="true"><rect x="2" y="3" width="4" height="4" rx="1" fill="var(--hand)"/><rect x="8" y="3" width="10" height="4" rx="1" fill="currentColor" opacity=".9"/><rect x="2" y="9" width="4" height="4" rx="1" fill="currentColor" opacity=".45"/><rect x="8" y="9" width="7" height="4" rx="1" fill="currentColor" opacity=".45"/><rect x="2" y="15" width="4" height="3" rx="1" fill="currentColor" opacity=".25"/><rect x="8" y="15" width="9" height="3" rx="1" fill="currentColor" opacity=".25"/></svg>
        mcl-kanban
      </a>
      <div class="seg" role="group" aria-label="View">
        <button type="button" aria-pressed={to_string(@nav["view"] == "pkg")} phx-click="view" phx-value-view="pkg">Packages <kbd>1</kbd></button>
        <button type="button" aria-pressed={to_string(@nav["view"] == "repo")} phx-click="view" phx-value-view="repo">Repos <kbd>2</kbd></button>
      </div>
      <form id="search-form" class="search" phx-change="search" phx-submit="search" role="search">
        <label for="q" class="sr">Find a card</label>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>
        <input id="q" name="q" value={@nav["q"]} placeholder="Find a card, repo or agent" autocomplete="off" phx-debounce="200" />
        <kbd>/</kbd>
      </form>
      <div class="chips">
        <.chip id="f-blocked" class="chip blocked" key="blocked" label="Blocked" nav={@nav} n={Enum.count(@cards, &(&1.state == "blocked"))} />
        <.chip id="f-live" class="chip" key="live" label="In hand" nav={@nav} n={Enum.count(@cards, &(&1.state == "claimed"))} />
        <.chip id="f-pinned" class="chip" key="pinned" label="Pinned" nav={@nav} n={Enum.count(@cards, &(&1.pinned == 1))} />
      </div>
      <span class="spacer"></span>
      <button type="button" class="iconbtn theme" data-theme-toggle aria-label="Switch light or dark">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 3a9 9 0 0 0 0 18z" fill="currentColor"/></svg>
      </button>
      <span class="owner" title="This UI acts as the owner: it answers only the box's own network, behind its router"><i aria-hidden="true"></i>Owner</span>
    </header>
    """
  end

  attr(:id, :string, required: true)
  attr(:class, :string, required: true)
  attr(:key, :string, required: true)
  attr(:label, :string, required: true)
  attr(:nav, :map, required: true)
  attr(:n, :integer, required: true)

  defp chip(assigns) do
    ~H"""
    <button type="button" id={@id} class={@class} data-n={@n} aria-pressed={to_string(@nav["filter"] == @key)} phx-click="filter" phx-value-filter={@key}>
      {@label} <b>{@n}</b>
    </button>
    """
  end

  # ---------- boards nav ----------

  attr(:nav, :map, required: true)
  attr(:packages, :list, required: true)
  attr(:cards, :list, required: true)

  def boards_nav(assigns) do
    assigns =
      assign(assigns,
        repos: assigns.cards |> Enum.map(& &1.board) |> Enum.uniq() |> Enum.sort(),
        loose: Enum.filter(assigns.cards, &(&1.work_package == nil))
      )

    ~H"""
    <nav class="nav" aria-label="Boards">
      <h2>Work packages</h2>
      <ul>
        <.nav_item href={nav_href("pkg", "all")} name="All packages" cards={@cards} current={@nav["view"] == "pkg" and @nav["focus"] == "all"} />
        <.nav_item
          :for={p <- @packages}
          href={nav_href("pkg", p.issue_ref)}
          name={"#{p.rank || "–"}  #{short_ref(p.issue_ref)}"}
          title={p.title}
          cards={p.cards}
          current={@nav["view"] == "pkg" and @nav["focus"] == p.issue_ref}
        />
        <.nav_item href={nav_href("pkg", "loose")} name="Not in a package" cards={@loose} current={@nav["view"] == "pkg" and @nav["focus"] == "loose"} />
      </ul>
      <h2>Repos</h2>
      <ul>
        <.nav_item href={nav_href("repo", "all")} name="All repos" cards={@cards} current={@nav["view"] == "repo" and @nav["focus"] == "all"} />
        <.nav_item
          :for={r <- @repos}
          href={nav_href("repo", r)}
          name={short_repo(r)}
          title={r}
          cards={Enum.filter(@cards, &(&1.board == r))}
          current={@nav["view"] == "repo" and @nav["focus"] == r}
        />
      </ul>
      <button type="button" id="open-board-btn" class="enlist" phx-click="open_dialog" phx-value-dialog="open_board">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>Open a board
      </button>
    </nav>
    """
  end

  attr(:href, :string, required: true)
  attr(:name, :string, required: true)
  attr(:title, :string, default: nil)
  attr(:cards, :list, required: true)
  attr(:current, :boolean, required: true)

  defp nav_item(assigns) do
    assigns = assign(assigns, cn: counts(assigns.cards))

    ~H"""
    <li>
      <.link patch={@href} aria-current={to_string(@current)} title={@title}>
        <span class="name">{@name}</span>
        <span class="navmeta"><.bar cn={@cn} class="bar" /><span class="n">{open_n(@cn)}</span></span>
      </.link>
    </li>
    """
  end

  attr(:cn, :map, required: true)
  attr(:class, :string, required: true)

  defp bar(assigns) do
    assigns =
      assign(assigns, t: max(assigns.cn.q + assigns.cn.c + assigns.cn.b + assigns.cn.d, 1))

    ~H"""
    <span class={@class} aria-hidden="true"><i class="d" style={"width:#{@cn.d / @t * 100}%"}></i><i class="c" style={"width:#{@cn.c / @t * 100}%"}></i><i class="b" style={"width:#{@cn.b / @t * 100}%"}></i><i class="q" style={"width:#{@cn.q / @t * 100}%"}></i></span>
    """
  end

  # ---------- the ladder ----------

  attr(:group, :map, required: true)
  attr(:open, :boolean, required: true)
  attr(:view, :string, required: true)
  attr(:selected, :string, default: nil)
  attr(:by_id, :map, required: true)
  attr(:now, :integer, required: true)

  def group(assigns) do
    assigns = assign(assigns, cn: counts(assigns.group.all))

    ~H"""
    <section
      class={["pkg", @group.kind == :loose && "loose", @group.kind == :package && @group.package.pinned == 1 && "pinned-pkg", @group.deferred == 1 && "paused"]}
      data-key={@group.key}
      data-open={if @open, do: "1", else: "0"}
    >
      <.group_head group={@group} cn={@cn} open={@open} />
      <ul class="cards" role="listbox" aria-label="Cards">
        <.card_row :for={c <- @group.cards} card={c} view={@view} selected={@selected} by_id={@by_id} now={@now} />
      </ul>
    </section>
    """
  end

  defp group_head(%{group: %{kind: :package}} = assigns) do
    ~H"""
    <div class="pkg-head" role="button" tabindex="0" aria-expanded={to_string(@open)} phx-click="toggle_group" phx-value-key={@group.key}
      aria-label={"Package #{@group.package.issue_ref}, rank #{@group.package.rank || "none"}"}>
      <span class="prank">{@group.package.rank || "–"}<small>{if @group.package.pinned == 1, do: "Pinned", else: "Package"}</small></span>
      <div>
        <h2>{@group.package.title}<a href={IssueRef.url(@group.package.issue_ref)} target="_blank" rel="noopener">{@group.package.issue_ref} ↗</a></h2>
        <div class="pkg-meta">
          <span class="repos"><span :for={r <- @group.package.repos}>{short_repo(r)}</span></span>
          <span :if={@group.package.rationale not in [nil, ""]} class="why">{@group.package.rationale}</span>
        </div>
      </div>
      <div class="pkg-right">
        <.bar cn={@cn} class="progress" />
        <span class="count">{@cn.d}/{length(@group.all)} done<b :if={@cn.b > 0} class="blk"> · {@cn.b} blocked</b><b :if={@group.deferred == 1} class="paused-tag"> · paused</b></span>
        <.pause_toggle kind="package" key={@group.key} deferred={@group.deferred} />
        <span class="caret"><.caret /></span>
      </div>
    </div>
    """
  end

  defp group_head(%{group: %{kind: :loose}} = assigns) do
    ~H"""
    <div class="pkg-head" role="button" tabindex="0" aria-expanded={to_string(@open)} phx-click="toggle_group" phx-value-key="loose">
      <span class="prank">{length(@group.cards)}<small>Loose</small></span>
      <div>
        <h2>Not in a package</h2>
        <div class="pkg-meta"><span class="why">Claimed after every package. File a card into a package from its drawer.</span></div>
      </div>
      <div class="pkg-right"><span class="caret"><.caret /></span></div>
    </div>
    """
  end

  defp group_head(assigns) do
    ~H"""
    <div class="pkg-head" role="button" tabindex="0" aria-expanded={to_string(@open)} phx-click="toggle_group" phx-value-key={@group.key}>
      <span class="prank count-rank">{open_n(@cn)}<small>Open</small></span>
      <div><h2>{@group.key}<a href={"https://github.com/#{@group.key}/issues"} target="_blank" rel="noopener">issues ↗</a></h2></div>
      <div class="pkg-right">
        <.bar cn={@cn} class="progress" />
        <span class="count">{@cn.c} in hand<b :if={@cn.b > 0} class="blk"> · {@cn.b} blocked</b><b :if={@group.deferred == 1} class="paused-tag"> · paused</b></span>
        <.pause_toggle kind="repo" key={@group.key} deferred={@group.deferred} />
        <span class="caret"><.caret /></span>
      </div>
    </div>
    """
  end

  # Pause or resume a package or a repo (#17): paused, its cards stay queued
  # and nobody is handed one until it is resumed.
  attr(:kind, :string, required: true)
  attr(:key, :string, required: true)
  attr(:deferred, :integer, required: true)

  defp pause_toggle(%{deferred: 1} = assigns) do
    ~H"""
    <button type="button" class="btn sm" data-resume={@key} phx-click="resume_group" phx-value-kind={@kind} phx-value-key={@key}
      aria-label={"Resume #{@key}"}>Resume</button>
    """
  end

  defp pause_toggle(assigns) do
    ~H"""
    <button type="button" class="btn sm" data-pause={@key} phx-click="pause_group" phx-value-kind={@kind} phx-value-key={@key}
      aria-label={"Pause #{@key}: nobody is handed its cards until it is resumed"}>Pause</button>
    """
  end

  defp caret(assigns) do
    ~H"""
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
    """
  end

  defp pin_svg(assigns) do
    ~H"""
    <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M14 3l7 7-3 1-3 3 1 5-3 1-4-4-5 5-1-1 5-5-4-4 1-3 5 1 3-3z"/></svg>
    """
  end

  attr(:card, :map, required: true)
  attr(:view, :string, required: true)
  attr(:selected, :string, default: nil)
  attr(:by_id, :map, required: true)
  attr(:now, :integer, required: true)

  def card_row(assigns) do
    assigns = assign(assigns, blocker: blocker(assigns.card, assigns.by_id))

    ~H"""
    <li
      id={"c-" <> @card.card_id}
      class={["card", "is-" <> @card.state, @card.deferred == 1 && "is-paused"]}
      role="option"
      aria-selected={to_string(@selected == @card.card_id)}
      data-card-id={@card.card_id}
      data-card-ref={@card.issue_ref}
      draggable={to_string(@card.state != "finished")}
      tabindex="-1"
      style={"--kind:" <> kind_var(@card.kind)}
    >
      <span class={["rank", @card.rank == nil && "unranked"]} title={if @card.rank == nil, do: "Unranked: waits at the bottom until the prioritiser ranks it"}>
        {@card.rank || "–"}
        <button type="button" class="pin" aria-pressed={to_string(@card.pinned == 1)} phx-click="pin" phx-value-card_id={@card.card_id}
          aria-label={"#{if @card.pinned == 1, do: "Unpin", else: "Pin"} #{@card.issue_ref}"}><.pin_svg /></button>
      </span>
      <span class="stripe" aria-hidden="true"></span>
      <span class="body" phx-click="open" phx-value-card={@card.card_id}>
        <span class="ref">
          <span class="k">{@card.kind}</span>
          <span class="repo">{short_ref(@card.issue_ref)}</span>
          <span :if={@view == "repo" and @card.work_package} class="repo in-pkg">in {num(@card.work_package)}</span>
        </span>
        <span class="title">{@card.title}</span>
      </span>
      <span class="state">
        <.card_state card={@card} blocker={@blocker} now={@now} />
        <span :if={@card.comment_count > 0} class="cmt" data-seen-card={@card.card_id} data-n={@card.comment_count}
          title={"#{@card.comment_count} comments"}>
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" aria-hidden="true"><path d="M4 5h16v11H9l-5 4z"/></svg>{@card.comment_count}
        </span>
      </span>
    </li>
    """
  end

  defp card_state(%{card: %{state: "claimed"}} = assigns) do
    ~H"""
    <.holder name={@card.holder} dot="live" /><span class="elapsed">{since(@card.claimed_at, @now)}</span>
    """
  end

  defp card_state(%{card: %{state: "blocked"}} = assigns) do
    ~H"""
    <.holder :if={@card.holder} name={@card.holder} dot="blocked" />
    <span :if={!@card.holder} class="dot blocked" aria-label="blocked"></span>
    <span class="blk">blocked<span :if={@blocker}> by <a href="#" phx-click="open" phx-value-card={@blocker.card_id}>{short_ref(@blocker.issue_ref)}</a></span></span>
    """
  end

  defp card_state(%{card: %{state: "deferred"}} = assigns) do
    ~H"""
    <span class="paused-tag">deferred</span>
    """
  end

  defp card_state(%{card: %{state: "finished"}} = assigns) do
    ~H"""
    <span class="dot done" aria-hidden="true"></span><span class="elapsed">done{if @card.holder, do: " by #{@card.holder}"}</span>
    """
  end

  defp card_state(%{card: %{lane: lane}} = assigns) when is_binary(lane) do
    ~H"""
    <span class="lane">for <b>{@card.lane}</b></span>
    """
  end

  defp card_state(assigns) do
    ~H"""
    <span class="lane">open</span>
    """
  end

  attr(:name, :string, required: true)
  attr(:dot, :string, required: true)

  defp holder(assigns) do
    ~H"""
    <span class="holder"><span class="av" style={"--c:" <> avatar(@name)}>{initial(@name)}</span>{@name}<span class={"dot " <> @dot} aria-label={if @dot == "live", do: "working", else: "blocked"}></span></span>
    """
  end

  attr(:nav, :map, required: true)
  attr(:boards, :list, required: true)

  defp empty(%{nav: %{"q" => q}} = assigns) when q != "" do
    ~H"""
    <div class="empty"><h2>No card matches “{@nav["q"]}”</h2><p>Try the issue number, a repo name or an agent.</p>
      <button type="button" class="btn" phx-click="clear">Clear the search</button></div>
    """
  end

  defp empty(%{nav: %{"filter" => "blocked"}} = assigns) do
    ~H"""
    <div class="empty"><h2>Nothing is blocked</h2><p>Every card in hand is moving. Clear the filter to see the whole ladder.</p>
      <button type="button" class="btn" phx-click="clear">Show everything <kbd>b</kbd></button></div>
    """
  end

  defp empty(%{boards: []} = assigns) do
    ~H"""
    <div class="empty"><h2>No boards yet</h2><p>Open the first one and agents can queue its issues as cards.</p>
      <button type="button" class="btn primary" phx-click="open_dialog" phx-value-dialog="open_board">Open a board</button></div>
    """
  end

  defp empty(%{nav: %{"view" => "pkg"}} = assigns) do
    ~H"""
    <div class="empty"><h2>No work packages yet</h2>
      <p>Label a parent issue <b>work-package</b> and the sync (scripts/fill_board.sh) brings it here with its child cards. Until then, the Repos view has every card.</p>
      <button type="button" class="btn" phx-click="view" phx-value-view="repo">Switch to Repos <kbd>2</kbd></button></div>
    """
  end

  defp empty(assigns) do
    ~H"""
    <div class="empty"><h2>No open cards here</h2><p>Queue an issue as a card and it lands at the bottom, unranked.</p>
      <button type="button" class="btn primary" phx-click="open_dialog" phx-value-dialog="queue">Queue a card <kbd>n</kbd></button></div>
    """
  end

  # ---------- crew rail ----------

  attr(:crew, :list, required: true)
  attr(:now, :integer, required: true)

  def crew_rail(assigns) do
    ~H"""
    <aside class="rail" aria-label="Crew on duty">
      <h2>Crew on duty</h2>
      <p :if={@crew == []} class="doing idle">Nobody is enlisted yet. Enlist an agent by the node id its MACULA_MCP_AGENT key signs with, then appoint a supervisor.</p>
      <ul class="crew">
        <li :for={a <- @crew}>
          <span class="av" style={"--c:" <> avatar(a.name)}>{initial(a.name)}</span>
          <span class="who">
            {a.name}
            <span :for={r <- a.roles -- ["agent"]} class={["role", r == "supervisor" && "sup"]}>{r}</span>
            <details class="menu">
              <summary aria-label={"Actions for " <> a.name}>⋯</summary>
              <div class="menu-list" role="menu">
                <button :if={"supervisor" not in a.roles} type="button" role="menuitem" phx-click="appoint" phx-value-name={a.name} phx-value-role="supervisor">Appoint supervisor</button>
                <button :if={"prioritiser" not in a.roles} type="button" role="menuitem" phx-click="appoint" phx-value-name={a.name} phx-value-role="prioritiser">Appoint prioritiser</button>
                <button type="button" role="menuitem" phx-click="open_dialog" phx-value-dialog="reserve_for" phx-value-name={a.name}>Reserve a card</button>
                <button :if={"supervisor" not in a.roles} type="button" role="menuitem" class="danger" data-discharge={a.name}
                  phx-click="discharge" phx-value-name={a.name} data-confirm={"Discharge #{a.name}? Its cards stay where they are."}>Discharge</button>
              </div>
            </details>
          </span>
          <span class="doings">
            <span :if={a.held == []} class="doing idle">idle · next in lane: {if a.next, do: short_ref(a.next.issue_ref), else: "nothing reserved"}</span>
            <span :for={c <- a.held} class={["doing", c.state == "blocked" && "blk"]}>
              <span class={"dot " <> if(c.state == "blocked", do: "blocked", else: "live")}></span>
              <b tabindex="0" role="link" phx-click="open" phx-value-card={c.card_id}>{short_ref(c.issue_ref)}</b>
              {if c.state == "blocked", do: "blocked", else: since(c.claimed_at, @now)}
            </span>
          </span>
        </li>
      </ul>
      <button type="button" class="enlist" id="enlist-btn" phx-click="open_dialog" phx-value-dialog="enlist">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>Enlist an agent
      </button>
      <div class="keys">Keys <kbd>?</kbd>
        <dl>
          <dt><kbd>j</kbd><kbd>k</kbd></dt><dd>move</dd>
          <dt><kbd>⏎</kbd></dt><dd>open card</dd>
          <dt><kbd>⇧↑</kbd><kbd>⇧↓</kbd></dt><dd>re-rank (pins)</dd>
          <dt><kbd>p</kbd></dt><dd>pin / unpin</dd>
          <dt><kbd>b</kbd></dt><dd>only blocked</dd>
        </dl>
      </div>
    </aside>
    """
  end

  # ---------- drawer ----------

  attr(:card, :map, default: nil)
  attr(:by_id, :map, required: true)
  attr(:crew, :list, required: true)
  attr(:packages, :list, required: true)

  def drawer(%{card: nil} = assigns) do
    ~H"""
    <aside class="drawer" id="drawer" data-open="0" aria-hidden="true"></aside>
    """
  end

  def drawer(assigns) do
    assigns =
      assign(assigns,
        package: Enum.find(assigns.packages, &(&1.issue_ref == assigns.card.work_package)),
        blocker: blocker(assigns.card, assigns.by_id)
      )

    ~H"""
    <div class="scrim" data-open="1" phx-click="close"></div>
    <aside class="drawer" id="drawer" data-open="1" role="dialog" aria-modal="false" aria-label={"Card " <> @card.issue_ref}
      style={"--kind:" <> kind_var(@card.kind)} phx-hook="Seen" data-seen-card={@card.card_id} data-n={@card.comment_count}>
      <div class="d-head">
        <span class="k">{@card.kind}</span>
        <a href={IssueRef.url(@card.issue_ref)} target="_blank" rel="noopener">{@card.issue_ref} ↗</a>
        <button type="button" class="iconbtn close" phx-click="close" aria-label="Close (esc)">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4"><path d="M6 6l12 12M18 6 6 18"/></svg>
        </button>
      </div>
      <div class="d-body">
        <h2>{@card.title}</h2>
        <p :if={@card.story} class="story">{CardStory.sentence(@card.story)}.</p>
        <div class="rankbox">
          <span class={["big", @card.pinned == 1 && "hand"]}>{@card.rank || "–"}</span>
          <span class="txt">
            <.rank_words card={@card} />
            <span :if={@package}><br />In package <b>{num(@package.issue_ref)}</b>, rank {@package.rank || "–"}.</span>
          </span>
          <span class="ctl">
            <button type="button" aria-label="Move up" data-nudge="-1" data-card-id={@card.card_id}>▲</button>
            <button type="button" aria-label="Move down" data-nudge="1" data-card-id={@card.card_id}>▼</button>
          </span>
        </div>
        <div class="actions">
          <button type="button" class={["btn", @card.pinned != 1 && "hand"]} phx-click="pin" phx-value-card_id={@card.card_id}>
            {if @card.pinned == 1, do: "Unpin", else: "Pin at #{@card.rank || "…"}"} <kbd>p</kbd>
          </button>
          <form id="rank-form" class="rank-at" phx-submit="pin_at">
            <input type="hidden" name="card_id" value={@card.card_id} />
            <label for="rank-at" class="sr">Rank</label>
            <input id="rank-at" name="rank" type="number" min="0" placeholder="rank" required />
            <button type="submit" class="btn sm">Set</button>
          </form>
          <button :if={@card.state == "blocked"} type="button" class="btn" phx-click="unblock">Unblock</button>
          <button :if={@card.state == "queued"} type="button" class="btn" phx-click="open_dialog" phx-value-dialog="reason" phx-value-action="defer">Defer</button>
          <button :if={@card.state == "deferred"} type="button" class="btn" phx-click="resume">Resume</button>
          <button :if={@card.state in ["claimed", "blocked"]} type="button" class="btn" phx-click="open_dialog" phx-value-dialog="reason" phx-value-action="release">Release from {@card.holder}</button>
          <button :if={@card.state in ["queued", "claimed"]} type="button" class="btn" phx-click="open_dialog" phx-value-dialog="reason" phx-value-action="block">Block</button>
          <form :if={@card.state == "queued"} id="reserve-form" class="btn lanepick" phx-change="reserve">
            <label for="lane">Reserve for</label>
            <select id="lane" name="lane" class="sel">
              <option value="">nobody</option>
              <option :for={a <- @crew} value={a.name} selected={@card.lane == a.name}>{a.name}</option>
            </select>
          </form>
          <button :if={@card.state not in ["finished", "withdrawn"]} type="button" class="btn danger" phx-click="open_dialog" phx-value-dialog="reason" phx-value-action="withdraw">Withdraw</button>
        </div>
        <dl class="facts">
          <dt>State</dt>
          <dd>{@card.state}<span :if={@card.holder}> by <b>{@card.holder}</b></span><span :if={@card.note} class={@card.state == "blocked" && "blk"}>: {@card.note}</span></dd>
          <dt>Lane</dt>
          <dd :if={@card.lane}>reserved for <b>{@card.lane}</b></dd>
          <dd :if={!@card.lane}>open to any agent</dd>
          <dt>Repo</dt><dd>{@card.board}</dd>
          <dt>Kind</dt>
          <dd>
            <form id="kind-form" phx-change="reclassify">
              <label for="kind" class="sr">Kind</label>
              <select id="kind" name="kind" class="sel">
                <option :for={k <- CardKind.kinds()} value={k} selected={k == @card.kind}>{k}</option>
              </select>
            </form>
          </dd>
          <dt>Package</dt>
          <dd>
            <form id="package-form" phx-change="file">
              <label for="package" class="sr">Package</label>
              <select id="package" name="package" class="sel">
                <option value="">none</option>
                <option :for={p <- @packages} value={p.issue_ref} selected={p.issue_ref == @card.work_package}>{short_ref(p.issue_ref)}: {String.slice(p.title, 0, 40)}</option>
              </select>
            </form>
          </dd>
        </dl>
        <h3 :if={@card.links != [] or @card.linked_from != []}>Links</h3>
        <ul class="links">
          <li :for={l <- @card.links}>
            <span class={["rel", l.link == "blocks" && "blk"]}>{l.link |> String.replace("_", " ")}</span>
            <.card_link id={l.to_card_id} by_id={@by_id} />
          </li>
          <li :for={l <- @card.linked_from}>
            <span class={["rel", l.link == "blocks" && "blk"]}>{reverse(l.link)}</span>
            <.card_link id={l.from_card_id} by_id={@by_id} />
          </li>
        </ul>
        <h3>Tags</h3>
        <div class="tags">
          <span :for={t <- @card.tags}>{t}<button type="button" class="untag" phx-click="untag" phx-value-tag={t} aria-label={"Remove tag " <> t}>×</button></span>
          <form id="tag-form" phx-submit="tag" class="tag-add">
            <label for="tag" class="sr">Add a tag</label>
            <input id="tag" name="tag" placeholder="+ tag" autocomplete="off" />
          </form>
        </div>
        <h3>Comments · {@card.comment_count}</h3>
        <ul class="thread">
          <li :if={@card.comments == []}><p class="mute">No comments yet. Agents post handoffs and blockers here; it never mirrors to GitHub.</p></li>
          <li :for={m <- @card.comments}>
            <div class={["by", m.author_kind]}><b>{m.author}</b><time>{at(m.at)}</time></div>
            <p>{m.text}</p>
          </li>
        </ul>
        <form id="comment-form" class="compose" phx-submit="comment">
          <label for="comment-text" class="sr">Comment</label>
          <textarea id="comment-text" name="text" placeholder="Comment as owner" required></textarea>
          <div class="row"><span>Recorded as the owner <kbd>c</kbd> to focus</span><button class="btn primary sm" type="submit">Comment</button></div>
        </form>
      </div>
    </aside>
    """
  end

  defp rank_words(%{card: %{rank: nil}} = assigns),
    do: ~H"<b>Unranked.</b> Waits at the bottom until the prioritiser ranks it."

  defp rank_words(%{card: %{pinned: 1}} = assigns),
    do:
      ~H"<b>Pinned by you.</b> The prioritiser cannot move it until you unpin. {@card.rationale}"

  defp rank_words(assigns), do: ~H"<b>Ranked by {@card.ranked_by}.</b> {@card.rationale}"

  attr(:id, :string, required: true)
  attr(:by_id, :map, required: true)

  defp card_link(assigns) do
    assigns = assign(assigns, other: Map.get(assigns.by_id, assigns.id))

    ~H"""
    <a :if={@other} href="#" phx-click="open" phx-value-card={@id}>{short_ref(@other.issue_ref)}</a>
    <span :if={@other} class="mute">{String.slice(@other.title, 0, 48)}</span>
    <code :if={!@other}>{@id}</code>
    """
  end

  defp reverse("blocks"), do: "blocked by"
  defp reverse("follows_up"), do: "followed up by"
  defp reverse("relates_to"), do: "related from"

  # ---------- toasts ----------

  attr(:toast, :map, required: true)

  def toast(%{toast: %{type: :err}} = assigns) do
    ~H"""
    <div id={@toast.id} class="toast err" role="alert" data-reason={@toast.reason} phx-hook="Toast">
      <span class="msg">{Phoenix.HTML.raw(@toast.text)} <span class="fix">{@toast.fix}</span></span>
      <button type="button" phx-click="dismiss_toast" phx-value-id={@toast.id}>OK</button>
    </div>
    """
  end

  def toast(%{toast: %{type: :rank}} = assigns) do
    ~H"""
    <div id={@toast.id} class="toast" phx-hook="Toast" data-sticky="1">
      <span class="msg">{Phoenix.HTML.raw(@toast.label)} → rank {@toast.rank}, pinned.<span :if={@toast.moved_to}> Moved into {moved(@toast.moved_to)}.</span></span>
      <form phx-submit="rationale">
        <input type="hidden" name="toast" value={@toast.id} />
        <input name="text" placeholder="Why? (optional)" aria-label="Rationale" autocomplete="off" />
      </form>
      <button :if={@toast.undo} type="button" data-undo phx-click="undo" phx-value-toast={@toast.id}>Undo</button>
      <button type="button" phx-click="dismiss_toast" phx-value-id={@toast.id} aria-label="Dismiss">×</button>
    </div>
    """
  end

  def toast(assigns) do
    ~H"""
    <div id={@toast.id} class="toast" phx-hook="Toast">
      <span class="msg">{Phoenix.HTML.raw(@toast.html)}</span>
      <button type="button" phx-click="dismiss_toast" phx-value-id={@toast.id} aria-label="Dismiss">×</button>
    </div>
    """
  end

  defp moved("loose"), do: "the loose cards"
  defp moved(ref), do: num(ref)

  # ---------- dialogs ----------

  # showModal() sets <dialog open> in the browser; a server patch (every
  # phx-change keystroke) would strip it, close the dialog and lose what the
  # owner typed. The server never owns that attribute.
  defp keep_open, do: JS.ignore_attributes(["open"])

  attr(:dialog, :any, required: true)
  attr(:enlist, :map, required: true)
  attr(:values, :map, default: %{})
  attr(:boards, :list, required: true)
  attr(:card, :map, default: nil)
  attr(:cards, :list, required: true)
  attr(:crew, :list, required: true)

  def dialogs(%{dialog: :enlist} = assigns) do
    ~H"""
    <dialog id="enlist" phx-hook="Dialog" phx-mounted={keep_open()}>
      <form id="enlist-form" phx-change="validate_enlist" phx-submit="enlist">
        <h2>Enlist an agent</h2>
        <p class="lead">The node id is what the agent's MACULA_MCP_AGENT key signs with. Paste it from the agent's first <em>info</em> reply.</p>
        <div class="field">
          <label for="e-name">Name</label>
          <input id="e-name" name="name" value={@values["name"]} placeholder="Mercury" required autocomplete="off" phx-debounce="150" aria-invalid={to_string(elem(@enlist.name, 0) == :bad)} />
          <span class={["hint", hint_class(@enlist.name)]}>{elem(@enlist.name, 1)}</span>
        </div>
        <div class="field">
          <label for="e-node">Node id</label>
          <input id="e-node" name="node_id" value={@values["node_id"]} placeholder="64 hex characters" required spellcheck="false" autocomplete="off" phx-debounce="150" aria-invalid={to_string(elem(@enlist.node, 0) == :bad)} />
          <span class={["hint", hint_class(@enlist.node)]}>{elem(@enlist.node, 1)}</span>
        </div>
        <div class="field">
          <label for="e-role">Role</label>
          <select id="e-role" name="role">
            <option value="agent">Agent</option>
            <option value="supervisor" selected={@values["role"] == "supervisor"}>Agent, and appoint as supervisor</option>
            <option value="prioritiser" selected={@values["role"] == "prioritiser"}>Agent, and appoint as prioritiser</option>
          </select>
        </div>
        <div class="row"><button class="btn" type="button" phx-click="close_dialog">Cancel</button><button class="btn primary" type="submit">Enlist</button></div>
      </form>
    </dialog>
    """
  end

  def dialogs(%{dialog: :open_board} = assigns) do
    ~H"""
    <dialog id="open-board" phx-hook="Dialog" phx-mounted={keep_open()}>
      <form id="open-board-form" phx-change="dialog_change" phx-submit="open_board">
        <h2>Open a board</h2>
        <p class="lead">One board per GitHub repo. Agents then queue its issues as cards.</p>
        <div class="field">
          <label for="ob-repo">Repo</label>
          <input id="ob-repo" name="repo" value={@values["repo"]} placeholder="owner/repo" required autocomplete="off" pattern="[A-Za-z0-9][A-Za-z0-9_.\-]*/[A-Za-z0-9_.\-]+" />
          <span class="hint">As on GitHub: owner/repo</span>
        </div>
        <div class="row"><button class="btn" type="button" phx-click="close_dialog">Cancel</button><button class="btn primary" type="submit">Open the board</button></div>
      </form>
    </dialog>
    """
  end

  def dialogs(%{dialog: :queue} = assigns) do
    ~H"""
    <dialog id="queue" phx-hook="Dialog" phx-mounted={keep_open()}>
      <form :if={@boards != []} id="queue-form" phx-change="dialog_change" phx-submit="queue_card">
        <h2>Queue a card</h2>
        <p class="lead">A card is a GitHub issue. It lands at the bottom, unranked, until it is ranked.</p>
        <div class="field-row">
          <div class="field grow">
            <label for="qc-repo">Repo</label>
            <select id="qc-repo" name="repo"><option :for={b <- @boards} value={b.repo} selected={@values["repo"] == b.repo}>{b.repo}</option></select>
          </div>
          <div class="field num">
            <label for="qc-number">Issue</label>
            <input id="qc-number" name="number" value={@values["number"]} type="number" min="1" placeholder="#" required />
          </div>
        </div>
        <div class="field"><label for="qc-title">Title</label><input id="qc-title" name="title" value={@values["title"]} required maxlength="200" placeholder="The issue's title" /></div>
        <div class="field">
          <label for="qc-kind">Kind</label>
          <select id="qc-kind" name="kind"><option :for={k <- CardKind.kinds()} value={k} selected={@values["kind"] == k}>{k}</option></select>
        </div>
        <details class="more">
          <summary>Story and tags</summary>
          <div class="field"><label for="qc-role">As a</label><input id="qc-role" name="role" value={@values["role"]} placeholder="fleet operator" /></div>
          <div class="field"><label for="qc-ask">I want</label><input id="qc-ask" name="ask" value={@values["ask"]} /></div>
          <div class="field"><label for="qc-value">so that</label><input id="qc-value" name="value" value={@values["value"]} /><span class="hint">All three parts, or none.</span></div>
          <div class="field"><label for="qc-tags">Tags</label><input id="qc-tags" name="tags" value={@values["tags"]} placeholder="comma, separated" /></div>
        </details>
        <div class="row"><button class="btn" type="button" phx-click="close_dialog">Cancel</button><button class="btn primary" type="submit">Queue the card</button></div>
      </form>
      <form :if={@boards == []} method="dialog">
        <h2>No boards yet</h2>
        <p class="lead">A card lives on its repo's board. Open the board first.</p>
        <div class="row"><button class="btn" type="button" phx-click="close_dialog">Cancel</button><button class="btn primary" type="button" phx-click="open_dialog" phx-value-dialog="open_board">Open a board</button></div>
      </form>
    </dialog>
    """
  end

  def dialogs(%{dialog: {:reason, action}, card: card} = assigns) when card != nil do
    assigns = assign(assigns, action: action)

    ~H"""
    <dialog id="reason" phx-hook="Dialog" phx-mounted={keep_open()}>
      <form id="reason-form" phx-change="dialog_change" phx-submit="reason">
        <input type="hidden" name="action" value={@action} />
        <h2>{reason_title(@action)} {short_ref(@card.issue_ref)}</h2>
        <p class="lead">{reason_lead(@action)}</p>
        <div class="field"><label for="r-reason">Why</label><input id="r-reason" name="reason" value={@values["reason"]} required={@action != "withdraw"} autocomplete="off" /></div>
        <div class="row">
          <button class="btn" type="button" phx-click="close_dialog">Cancel</button>
          <button class={["btn", if(@action == "withdraw", do: "danger", else: "primary")]} type="submit"
            data-confirm={if @action == "withdraw", do: "Withdraw #{@card.issue_ref}? It leaves the board."}>{reason_title(@action)}</button>
        </div>
      </form>
    </dialog>
    """
  end

  def dialogs(%{dialog: {:pause, kind, key}} = assigns) do
    assigns = assign(assigns, kind: kind, key: key)

    ~H"""
    <dialog id="pause" phx-hook="Dialog" phx-mounted={keep_open()}>
      <form id="pause-form" phx-change="dialog_change" phx-submit="pause">
        <input type="hidden" name="kind" value={@kind} />
        <input type="hidden" name="key" value={@key} />
        <h2>Pause {@key}</h2>
        <p class="lead">Its cards stay queued, and nobody is handed one until you resume it. No card is marked blocked.<span :if={@kind == "package"}> The package loses its rank.</span></p>
        <div class="field"><label for="p-reason">Why</label><input id="p-reason" name="reason" value={@values["reason"]} required autocomplete="off" /></div>
        <div class="row">
          <button class="btn" type="button" phx-click="close_dialog">Cancel</button>
          <button class="btn primary" type="submit">Pause</button>
        </div>
      </form>
    </dialog>
    """
  end

  def dialogs(%{dialog: {:reserve_for, name}} = assigns) do
    assigns =
      assign(assigns,
        name: name,
        open: Enum.filter(assigns.cards, &(&1.state == "queued" and &1.lane == nil))
      )

    ~H"""
    <dialog id="reserve-for" phx-hook="Dialog" phx-mounted={keep_open()}>
      <form id="reserve-for-form" phx-change="dialog_change" phx-submit="reserve_for">
        <input type="hidden" name="lane" value={@name} />
        <h2>Reserve a card for {@name}</h2>
        <p class="lead">Only {@name} may then claim it.</p>
        <div :if={@open != []} class="field">
          <label for="rf-card">Card</label>
          <select id="rf-card" name="card_id"><option :for={c <- @open} value={c.card_id} selected={@values["card_id"] == c.card_id}>{short_ref(c.issue_ref)}: {String.slice(c.title, 0, 60)}</option></select>
        </div>
        <p :if={@open == []} class="lead">Every queued card is reserved already.</p>
        <div class="row"><button class="btn" type="button" phx-click="close_dialog">Cancel</button><button :if={@open != []} class="btn primary" type="submit">Reserve</button></div>
      </form>
    </dialog>
    """
  end

  def dialogs(%{dialog: :help} = assigns) do
    ~H"""
    <dialog id="help" phx-hook="Dialog" phx-mounted={keep_open()}>
      <form method="dialog">
        <h2>Keys</h2>
        <p class="lead">Nothing here needs the mouse.</p>
        <div class="helpkeys">
          <div><span>Packages view</span><kbd>1</kbd></div><div><span>Repos view</span><kbd>2</kbd></div>
          <div><span>Find</span><kbd>/</kbd></div><div><span>Move selection</span><span><kbd>j</kbd> <kbd>k</kbd></span></div>
          <div><span>Open / close card</span><span><kbd>⏎</kbd> <kbd>esc</kbd></span></div><div><span>Re-rank selected (pins)</span><span><kbd>⇧↑</kbd> <kbd>⇧↓</kbd></span></div>
          <div><span>Pin / unpin</span><kbd>p</kbd></div><div><span>Only blocked</span><kbd>b</kbd></div>
          <div><span>Comment on open card</span><kbd>c</kbd></div><div><span>Queue a card</span><kbd>n</kbd></div>
          <div><span>Collapse / expand group</span><kbd>space</kbd></div><div><span>This list</span><kbd>?</kbd></div>
        </div>
        <div class="row"><button class="btn primary" type="button" phx-click="close_dialog">Close</button></div>
      </form>
    </dialog>
    """
  end

  def dialogs(assigns), do: ~H""

  defp hint_class({:ok, _}), do: "ok"
  defp hint_class({:bad, _}), do: "bad"
  defp hint_class(_neutral), do: nil

  defp reason_title("release"), do: "Release"
  defp reason_title("block"), do: "Block"
  defp reason_title("withdraw"), do: "Withdraw"
  defp reason_title("defer"), do: "Defer"

  defp reason_lead("release"),
    do: "The card goes back to the queue, and the holder's work on it stops."

  defp reason_lead("block"), do: "Name what it waits for, usually another card."

  defp reason_lead("defer"),
    do:
      "Not now: nobody is handed it until you resume it. It loses its rank and comes back unranked."

  defp reason_lead("withdraw"),
    do: "The card leaves the board for good; the issue stays on GitHub."
end
