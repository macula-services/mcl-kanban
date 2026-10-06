defmodule MclKanbanWeb.BoardLive do
  # One board: queued (in rank order), claimed, blocked, finished; a card
  # drawer with the story, tags, links both ways, the comment thread, a link
  # to the issue, and the owner's actions. Live from the read model.
  @moduledoc false

  use Phoenix.LiveView

  import MclKanbanWeb.CardComponents

  alias GuideCardLifecycle.CardKind
  alias GuideCardLifecycle.CardStory
  alias GuideCardLifecycle.IssueRef
  alias MclKanbanWeb.OwnerActions
  alias ProjectBoards.BoardsChanged
  alias QueryBoards.GetBoardByRepo.GetBoardByRepo
  alias QueryBoards.GetCardById.GetCardById
  alias QueryBoards.GetCrew.GetCrew

  @columns [
    {"queued", "Queued"},
    {"claimed", "Claimed"},
    {"blocked", "Blocked"},
    {"finished", "Finished"}
  ]

  @impl true
  def mount(%{"owner" => owner, "name" => name}, _session, socket) do
    if connected?(socket),
      do: :ok = Phoenix.PubSub.subscribe(MclKanbanWeb.PubSub, BoardsChanged.topic())

    repo = owner <> "/" <> name

    {:ok,
     socket
     |> assign(
       repo: repo,
       page_title: repo <> " · mcl-kanban",
       notice: nil,
       selected: nil,
       columns: @columns
     )
     |> load()}
  end

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, socket |> assign(selected: params["card"]) |> load()}

  defp load(%{assigns: %{repo: repo, selected: selected}} = socket) do
    {board, cards} =
      case GetBoardByRepo.get_board_by_repo(repo) do
        {:ok, %{board: board, cards: cards}} -> {board, cards}
        {:error, :unknown_board} -> {nil, []}
      end

    assign(socket,
      board: board,
      by_state: Enum.group_by(cards, & &1.state),
      card: drawer(selected),
      crew: GetCrew.get_crew()
    )
  end

  defp drawer(nil), do: nil

  defp drawer(card_id) do
    case GetCardById.get_card_by_id(card_id) do
      {:ok, card} -> card
      {:error, _} -> nil
    end
  end

  @impl true
  def handle_info({:boards_changed, _change}, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("select", %{"card" => card_id}, socket),
    do:
      {:noreply, push_patch(socket, to: "/boards/" <> socket.assigns.repo <> "?card=" <> card_id)}

  def handle_event("close", _params, socket),
    do: {:noreply, push_patch(socket, to: "/boards/" <> socket.assigns.repo)}

  def handle_event("dismiss", _params, socket), do: {:noreply, assign(socket, notice: nil)}

  def handle_event("open_board", _params, socket),
    do: done(socket, OwnerActions.open_board(socket.assigns.repo), "Board opened")

  def handle_event("queue_card", params, socket),
    do: done(socket, OwnerActions.queue_card(params), "Card queued")

  def handle_event(action, params, %{assigns: %{selected: card_id}} = socket)
      when is_binary(card_id),
      do: done(socket, card_action(action, card_id, params), "Done")

  defp card_action("rank", id, p), do: OwnerActions.rank(id, p["rank"], p["rationale"])
  defp card_action("unpin", id, _p), do: OwnerActions.unpin(id)
  defp card_action("reserve", id, p), do: OwnerActions.reserve(id, p["lane"])
  defp card_action("lift", id, _p), do: OwnerActions.lift(id)
  defp card_action("withdraw", id, p), do: OwnerActions.withdraw(id, p["reason"])
  defp card_action("release", id, p), do: OwnerActions.release(id, p["reason"])
  defp card_action("block", id, p), do: OwnerActions.block(id, p["reason"])
  defp card_action("unblock", id, _p), do: OwnerActions.unblock(id)
  defp card_action("reclassify", id, p), do: OwnerActions.reclassify(id, p["kind"])
  defp card_action("reword", id, p), do: OwnerActions.reword(id, p)
  defp card_action("comment", id, p), do: OwnerActions.comment(id, p["text"])
  defp card_action("tag", id, p), do: OwnerActions.tag(id, p["tag"])
  defp card_action("untag", id, p), do: OwnerActions.untag(id, p["tag"])

  defp done(socket, :ok, message),
    do: {:noreply, socket |> assign(notice: {"ok", message}) |> load()}

  defp done(socket, {:error, reason}, _message),
    do: {:noreply, assign(socket, notice: refused(reason))}

  @impl true
  def render(assigns) do
    ~H"""
    <.header><a href="/">All boards</a> <span aria-hidden="true">›</span> {@repo}</.header>
    <main class="board">
      <.notice notice={@notice} />

      <section :if={@board == nil} class="panel empty-board">
        <h2>No board for {@repo} yet</h2>
        <p>Open it, and agents can queue this repo's issues as cards.</p>
        <button type="button" phx-click="open_board">Open the board</button>
      </section>

      <div :if={@board} class="columns">
        <section :for={{state, label} <- @columns} class={"column col-" <> state} aria-labelledby={"col-" <> state}>
          <h2 id={"col-" <> state}>{label} <span class="n">{length(Map.get(@by_state, state, []))}</span></h2>
          <p :if={Map.get(@by_state, state, []) == []} class="empty">Nothing {state}.</p>
          <ul>
            <li :for={c <- Map.get(@by_state, state, [])}><.tile card={c} selected={@selected} /></li>
          </ul>
        </section>
      </div>

      <details :if={@board} class="panel queue-form" open={@by_state == %{}}>
        <summary>Queue a card <kbd>n</kbd></summary>
        <form id="queue-card" phx-submit="queue_card" class="stack">
          <label>Issue <input name="issue_ref" value={@repo <> "#"} data-shortcut="n" autocomplete="off" required /></label>
          <label>Title <input name="title" required /></label>
          <label>Kind
            <select name="kind">
              <option :for={k <- CardKind.kinds()} value={k}>{k}</option>
            </select>
          </label>
          <label>Tags <input name="tags" placeholder="comma, separated" /></label>
          <fieldset class="story">
            <legend>Story (optional): As a … I want … so that …</legend>
            <input name="role" placeholder="role" aria-label="As a" />
            <input name="ask" placeholder="ask" aria-label="I want" />
            <input name="value" placeholder="value" aria-label="so that" />
          </fieldset>
          <button type="submit">Queue</button>
        </form>
      </details>

      <aside :if={@card} class="drawer" role="dialog" aria-label={"Card " <> @card.issue_ref} style={"--kind: " <> @card.colour}>
        <header>
          <.kind kind={@card.kind} />
          <a class="ref" href={IssueRef.url(@card.issue_ref)} target="_blank" rel="noopener">{@card.issue_ref} ↗</a>
          <button type="button" class="close" phx-click="close" data-close-drawer aria-label="Close (Esc)">×</button>
        </header>
        <h2>{@card.title}</h2>
        <p :if={@card.story} class="story-text">{CardStory.sentence(@card.story)}</p>
        <dl class="facts">
          <dt>State</dt><dd>{@card.state}<span :if={@card.note}> · {@card.note}</span></dd>
          <dt>Rank</dt>
          <dd>
            {@card.rank || "unranked"}
            <span :if={@card.pinned == 1} class="pin">pinned</span>
            <span :if={@card.ranked_by}> by {@card.ranked_by}</span>
            <span :if={@card.rationale && @card.rationale != ""} class="why">: {@card.rationale}</span>
          </dd>
          <dt>Holder</dt><dd>{@card.holder || "nobody"}</dd>
          <dt>Lane</dt><dd>{@card.lane || "none"}</dd>
        </dl>

        <div class="tags">
          <span :for={t <- @card.tags} class="tag">
            {t}
            <button type="button" class="link" phx-click="untag" phx-value-tag={t} aria-label={"Remove tag " <> t}>×</button>
          </span>
          <form phx-submit="tag" class="inline small">
            <input name="tag" placeholder="add tag" aria-label="Add tag" />
          </form>
        </div>

        <section :if={@card.links != [] or @card.linked_from != []} class="links">
          <h3>Links</h3>
          <ul>
            <li :for={l <- @card.links}>{l.link} <code>{l.to_card_id}</code></li>
            <li :for={l <- @card.linked_from}>{reverse(l.link)} <code>{l.from_card_id}</code></li>
          </ul>
        </section>

        <section class="owner-actions" aria-label="Owner actions">
          <h3>Owner</h3>
          <form id="rank-card" phx-submit="rank" class="inline">
            <input name="rank" type="number" min="0" placeholder="rank" aria-label="Rank" required />
            <input name="rationale" placeholder="why (optional)" aria-label="Rationale" />
            <button type="submit">Pin rank</button>
          </form>
          <div class="buttons">
            <button :if={@card.pinned == 1} type="button" phx-click="unpin">Unpin</button>
            <button :if={@card.lane} type="button" phx-click="lift">Lift lane</button>
            <button :if={@card.state == "blocked"} type="button" phx-click="unblock">Unblock</button>
          </div>
          <form phx-submit="reserve" class="inline">
            <input name="lane" list="lane-agents" placeholder="agent" aria-label="Reserve for agent" required />
            <datalist id="lane-agents"><option :for={a <- @crew} value={a.name} /></datalist>
            <button type="submit">Reserve</button>
          </form>
          <form phx-submit="reclassify" class="inline">
            <select name="kind" aria-label="Kind">
              <option :for={k <- CardKind.kinds()} value={k} selected={k == @card.kind}>{k}</option>
            </select>
            <button type="submit">Reclassify</button>
          </form>
          <form :if={@card.state == "claimed"} phx-submit="release" class="inline">
            <input name="reason" placeholder="why release" aria-label="Release reason" required />
            <button type="submit">Release</button>
          </form>
          <form :if={@card.state in ["queued", "claimed"]} phx-submit="block" class="inline">
            <input name="reason" placeholder="blocked by" aria-label="Block reason" required />
            <button type="submit">Block</button>
          </form>
          <form :if={@card.state not in ["finished", "withdrawn"]} phx-submit="withdraw" class="inline">
            <input name="reason" placeholder="why withdraw" aria-label="Withdraw reason" />
            <button type="submit" class="danger" data-confirm="Withdraw this card?">Withdraw</button>
          </form>
        </section>

        <section class="thread" aria-label="Comments">
          <h3>Comments <span class="n">{@card.comment_count}</span></h3>
          <p :if={@card.comments == []} class="empty">No comments yet.</p>
          <ol>
            <li :for={c <- @card.comments} class={"by-" <> c.author_kind}>
              <span class="author">{c.author}</span> <time>{at(c.at)}</time>
              <p>{c.text}</p>
            </li>
          </ol>
          <form id="comment-card" phx-submit="comment" class="stack">
            <textarea name="text" rows="2" placeholder="Comment as owner" aria-label="Comment" required></textarea>
            <button type="submit">Comment</button>
          </form>
        </section>
      </aside>
    </main>
    """
  end

  defp reverse("blocks"), do: "blocked by"
  defp reverse("follows_up"), do: "followed up by"
  defp reverse("relates_to"), do: "related from"

  defp at(ms), do: ms |> DateTime.from_unix!(:millisecond) |> Calendar.strftime("%Y-%m-%d %H:%M")
end
