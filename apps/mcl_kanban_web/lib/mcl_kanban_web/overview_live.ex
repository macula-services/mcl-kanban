defmodule MclKanbanWeb.OverviewLive do
  # The owner's overview: every board, the crew and its two appointments,
  # and the all-boards queue in the one global rank order. Live from the read
  # model; every action goes through MclKanbanWeb.OwnerActions.
  @moduledoc false

  use Phoenix.LiveView

  import MclKanbanWeb.CardComponents

  alias MclKanbanWeb.OwnerActions
  alias ProjectBoards.BoardsChanged
  alias QueryBoards.GetBoards.GetBoards
  alias QueryBoards.GetCrew.GetCrew
  alias QueryBoards.GetRankedCards.GetRankedCards

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket),
      do: :ok = Phoenix.PubSub.subscribe(MclKanbanWeb.PubSub, BoardsChanged.topic())

    {:ok, socket |> assign(page_title: "mcl-kanban", notice: nil) |> load()}
  end

  defp load(socket) do
    assign(socket,
      boards: GetBoards.get_boards(),
      crew: GetCrew.get_crew(),
      ranked: GetRankedCards.get_ranked_cards()
    )
  end

  @impl true
  def handle_info({:boards_changed, _change}, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("open_board", %{"repo" => repo}, socket),
    do: done(socket, OwnerActions.open_board(String.trim(repo)), "Board #{repo} opened")

  def handle_event("enlist", params, socket),
    do: done(socket, OwnerActions.enlist(params), "#{params["name"]} enlisted")

  def handle_event("appoint_supervisor", %{"name" => name}, socket),
    do: done(socket, OwnerActions.appoint_supervisor(name), "#{name} is the supervisor")

  def handle_event("appoint_prioritiser", %{"name" => name}, socket),
    do: done(socket, OwnerActions.appoint_prioritiser(name), "#{name} is the prioritiser")

  def handle_event("discharge", %{"name" => name}, socket),
    do: done(socket, OwnerActions.discharge(name), "#{name} discharged")

  def handle_event("select", %{"card" => card_id}, socket) do
    card = Enum.find(socket.assigns.ranked, &(&1.card_id == card_id))
    {:noreply, push_navigate(socket, to: "/boards/" <> card.board <> "?card=" <> card_id)}
  end

  def handle_event("dismiss", _params, socket), do: {:noreply, assign(socket, notice: nil)}

  defp done(socket, :ok, message),
    do: {:noreply, socket |> assign(notice: {"ok", message}) |> load()}

  defp done(socket, {:error, reason}, _message),
    do: {:noreply, assign(socket, notice: refused(reason))}

  @impl true
  def render(assigns) do
    ~H"""
    <.header>All boards</.header>
    <main class="overview">
      <.notice notice={@notice} />

      <section class="panel boards" aria-labelledby="boards-h">
        <h2 id="boards-h">Boards</h2>
        <p :if={@boards == []} class="empty">
          No boards yet. Open one for a repo below; agents can then queue its issues as cards.
        </p>
        <ul class="board-list">
          <li :for={b <- @boards} class={b.archived == 1 && "archived"}>
            <a href={"/boards/" <> b.repo}>{b.repo}</a>
            <span class="counts" aria-label="queued, claimed, blocked, finished">
              <span title="queued">{b.counts.queued}</span>
              <span title="claimed">{b.counts.claimed}</span>
              <span title="blocked">{b.counts.blocked}</span>
              <span title="finished">{b.counts.finished}</span>
            </span>
          </li>
        </ul>
        <form id="open-board" phx-submit="open_board" class="inline">
          <label for="open-board-repo" class="sr">Repo</label>
          <input id="open-board-repo" name="repo" placeholder="owner/repo" autocomplete="off" required />
          <button type="submit">Open board</button>
        </form>
      </section>

      <section class="panel crew" aria-labelledby="crew-h">
        <h2 id="crew-h">Crew</h2>
        <p :if={@crew == []} class="empty">
          Nobody is enlisted. Enlist an agent by the node id its MACULA_MCP_IDENTITY key signs with,
          then appoint a supervisor.
        </p>
        <ul class="crew-list">
          <li :for={a <- @crew}>
            <span class="agent">{a.name}</span>
            <span :for={r <- a.roles -- ["agent"]} class={"role role-" <> r}>{r}</span>
            <code class="node" title={a.node_id}>{String.slice(a.node_id, 0, 12)}…</code>
            <button
              :if={"supervisor" not in a.roles}
              type="button"
              class="link danger"
              phx-click="discharge"
              phx-value-name={a.name}
              data-confirm={"Discharge " <> a.name <> "?"}
            >
              discharge
            </button>
          </li>
        </ul>
        <datalist id="agents">
          <option :for={a <- @crew} value={a.name} />
        </datalist>
        <form id="enlist-agent" phx-submit="enlist" class="stack">
          <label>Name <input name="name" autocomplete="off" required /></label>
          <label>Node id <input name="node_id" placeholder="64 hex characters" autocomplete="off" required /></label>
          <button type="submit">Enlist</button>
        </form>
        <div class="appoint">
          <form id="appoint-supervisor" phx-submit="appoint_supervisor" class="inline">
            <input name="name" list="agents" placeholder="agent" aria-label="Agent to appoint as supervisor" required />
            <button type="submit">Appoint supervisor</button>
          </form>
          <form id="appoint-prioritiser" phx-submit="appoint_prioritiser" class="inline">
            <input name="name" list="agents" placeholder="agent" aria-label="Agent to appoint as prioritiser" required />
            <button type="submit">Appoint prioritiser</button>
          </form>
        </div>
      </section>

      <section class="panel queue" aria-labelledby="queue-h">
        <h2 id="queue-h">Queue across all boards</h2>
        <p class="hint">One rank scale; lower is claimed first. Unranked cards wait at the bottom.</p>
        <p :if={@ranked == []} class="empty">No open cards.</p>
        <ol class="ranked">
          <li :for={c <- @ranked}><.tile card={c} show_board={true} /></li>
        </ol>
      </section>
    </main>
    """
  end
end
