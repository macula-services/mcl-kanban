defmodule MclKanbanWeb.LadderLive do
  # The owner's one view of the work (#9, the approved mock in
  # docs/design/owner-ui-v2-mock.html): the rank ladder, cut by work package
  # or by repo, with the crew on duty beside it and a card drawer.
  #
  # The URL holds what the owner is looking at (view, focus, filter, q, and
  # the open card), so a link reopens it. Selection, collapsed groups,
  # dialogs and toasts live in the socket. Every action goes through
  # MclKanbanWeb.OwnerActions, acting as the owner; every refusal becomes a
  # toast with what to do about it. Live from the read model.
  @moduledoc false

  use Phoenix.LiveView

  import MclKanbanWeb.LadderComponents

  alias MclKanbanWeb.OwnerActions
  alias ProjectBoards.BoardsChanged
  alias QueryBoards.GetBoards.GetBoards
  alias QueryBoards.GetCardById.GetCardById
  alias QueryBoards.GetCrew.GetCrew
  alias QueryBoards.GetLadder.GetLadder

  @params ~w(view focus filter q card)
  @defaults %{"view" => "pkg", "focus" => "all", "filter" => nil, "q" => "", "card" => nil}
  @reload_after_ms 200

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket),
      do: :ok = Phoenix.PubSub.subscribe(MclKanbanWeb.PubSub, BoardsChanged.topic())

    {:ok,
     assign(socket,
       page_title: "Crew board",
       selected: nil,
       reload: nil,
       collapsed: MapSet.new(),
       dialog: nil,
       toasts: [],
       values: %{},
       enlist: enlist_hints(%{})
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    nav = Map.merge(@defaults, Map.take(params, @params), fn _k, d, v -> blank(v, d) end)

    {:noreply,
     socket
     |> assign(nav: nav, selected: nav["card"] || socket.assigns.selected)
     |> load()}
  end

  defp blank("", default), do: default
  defp blank(value, _default), do: value

  # ---------- reading ----------

  defp load(socket) do
    %{packages: packages, loose: loose} = GetLadder.get_ladder()
    cards = Enum.flat_map(packages, & &1.cards) ++ loose

    socket
    |> assign(
      packages: packages,
      cards: cards,
      by_id: Map.new(cards, &{&1.card_id, &1}),
      crew: GetCrew.get_crew(),
      boards: Enum.filter(GetBoards.get_boards(), &(&1.archived == 0)),
      now: System.system_time(:millisecond)
    )
    |> assign_groups()
    |> assign(card: open_card(socket.assigns.nav["card"]))
  end

  defp open_card(nil), do: nil

  defp open_card(card_id) do
    case GetCardById.get_card_by_id(card_id) do
      {:ok, card} -> card
      {:error, _} -> nil
    end
  end

  defp assign_groups(%{assigns: %{nav: nav, cards: cards, packages: packages}} = socket) do
    visible = Enum.filter(cards, &shown?(&1, nav))
    assign(socket, groups: groups(nav["view"], nav, visible, packages, cards))
  end

  defp shown?(card, nav),
    do:
      focused?(card, nav["view"], nav["focus"]) and filtered?(card, nav["filter"]) and
        found?(card, nav["q"])

  defp focused?(_card, _view, "all"), do: true
  defp focused?(card, "pkg", "loose"), do: card.work_package == nil
  defp focused?(card, "pkg", ref), do: card.work_package == ref
  defp focused?(card, _repo_view, repo), do: card.board == repo

  defp filtered?(_card, nil), do: true
  defp filtered?(card, "blocked"), do: card.state == "blocked"
  defp filtered?(card, "live"), do: card.state == "claimed"
  defp filtered?(card, "pinned"), do: card.pinned == 1
  defp filtered?(_card, _unknown), do: true

  defp found?(_card, ""), do: true

  defp found?(card, q) do
    haystack = Enum.join([card.title, card.issue_ref, card.holder, card.lane | card.tags], " ")
    String.contains?(String.downcase(haystack), String.downcase(q))
  end

  defp groups("pkg", nav, visible, packages, all) do
    narrowed = nav["filter"] != nil or nav["q"] != ""

    in_packages =
      for p <- packages,
          nav["focus"] in ["all", p.issue_ref],
          cs = Enum.filter(visible, &(&1.work_package == p.issue_ref)),
          cs != [] or not narrowed,
          do: %{key: p.issue_ref, kind: :package, package: p, cards: cs, all: p.cards}

    loose = Enum.filter(visible, &(&1.work_package == nil))

    in_packages ++
      if(nav["focus"] in ["all", "loose"] and loose != [],
        do: [
          %{
            key: "loose",
            kind: :loose,
            cards: loose,
            all: Enum.filter(all, &(&1.work_package == nil))
          }
        ],
        else: []
      )
  end

  defp groups(_repo_view, nav, visible, _packages, all) do
    repos =
      case nav["focus"] do
        "all" -> visible |> Enum.map(& &1.board) |> Enum.uniq() |> Enum.sort()
        repo -> [repo]
      end

    for repo <- repos,
        do: %{
          key: repo,
          kind: :repo,
          cards: visible |> Enum.filter(&(&1.board == repo)) |> Enum.sort_by(&ladder_key/1),
          all: Enum.filter(all, &(&1.board == repo))
        }
  end

  defp ladder_key(c), do: {c.rank == nil, c.rank || 0, c.ranked_at || 0, c.queued_at}

  # A fill or a busy crew changes the board many times a second, and each
  # reload reads the whole ladder. Changes inside one window share a reload.
  @impl true
  def handle_info({:boards_changed, _change}, %{assigns: %{reload: nil}} = socket),
    do: {:noreply, assign(socket, reload: Process.send_after(self(), :reload, @reload_after_ms))}

  def handle_info({:boards_changed, _change}, socket), do: {:noreply, socket}

  def handle_info(:reload, socket), do: {:noreply, socket |> assign(reload: nil) |> load()}

  # ---------- navigation ----------

  @impl true
  def handle_event("view", %{"view" => view}, socket),
    do: {:noreply, patch(socket, %{"view" => view, "focus" => "all"})}

  def handle_event("focus", %{"view" => view, "focus" => focus}, socket),
    do: {:noreply, patch(socket, %{"view" => view, "focus" => focus})}

  def handle_event("filter", %{"filter" => filter}, socket),
    do: {:noreply, patch(socket, %{"filter" => toggle(socket.assigns.nav["filter"], filter)})}

  def handle_event("search", %{"q" => q}, socket),
    do: {:noreply, patch(socket, %{"q" => String.trim(q)})}

  def handle_event("clear", _params, socket),
    do: {:noreply, patch(socket, %{"filter" => nil, "q" => ""})}

  def handle_event("select", %{"card" => id}, socket),
    do: {:noreply, assign(socket, selected: id)}

  def handle_event("open", %{"card" => id}, socket),
    do: {:noreply, socket |> assign(selected: id) |> patch(%{"card" => id})}

  def handle_event("close", _params, socket), do: {:noreply, patch(socket, %{"card" => nil})}

  def handle_event("toggle_group", %{"key" => key}, %{assigns: %{collapsed: c}} = socket),
    do: {:noreply, assign(socket, collapsed: toggle_member(c, key))}

  # ---------- dialogs and toasts ----------

  def handle_event("open_dialog", %{"dialog" => dialog} = p, socket),
    do:
      {:noreply,
       assign(socket, dialog: dialog(dialog, p), values: %{}, enlist: enlist_hints(%{}))}

  # What the owner typed in a dialog, kept so any later render (a board change
  # on the pubsub, a hint) draws it back instead of clearing the field.
  def handle_event("dialog_change", params, socket),
    do: {:noreply, assign(socket, values: params)}

  def handle_event("close_dialog", _params, socket), do: {:noreply, assign(socket, dialog: nil)}

  def handle_event("dismiss_toast", %{"id" => id}, socket),
    do: {:noreply, update(socket, :toasts, &Enum.reject(&1, fn t -> t.id == id end))}

  def handle_event("dismiss_last_toast", _params, socket),
    do: {:noreply, update(socket, :toasts, &Enum.drop(&1, -1))}

  # ---------- the crew ----------

  def handle_event("validate_enlist", params, socket),
    do:
      {:noreply,
       assign(socket, values: params, enlist: enlist_hints(params, socket.assigns.crew))}

  def handle_event("enlist", params, socket) do
    socket
    |> assign(dialog: nil)
    |> outcome(OwnerActions.enlist_as(params), fn -> enlisted(params) end)
  end

  def handle_event("appoint", %{"name" => name, "role" => "supervisor"}, socket),
    do:
      outcome(socket, OwnerActions.appoint_supervisor(name), fn ->
        "<b>#{esc(name)}</b> is the supervisor"
      end)

  def handle_event("appoint", %{"name" => name, "role" => "prioritiser"}, socket),
    do:
      outcome(socket, OwnerActions.appoint_prioritiser(name), fn ->
        "<b>#{esc(name)}</b> is the prioritiser"
      end)

  def handle_event("discharge", %{"name" => name}, socket),
    do: outcome(socket, OwnerActions.discharge(name), fn -> "<b>#{esc(name)}</b> discharged" end)

  def handle_event("reserve_for", %{"lane" => lane, "card_id" => id}, socket) do
    socket
    |> assign(dialog: nil)
    |> outcome(OwnerActions.reserve(id, lane), fn ->
      "#{label(socket, id)} reserved for <b>#{esc(lane)}</b>"
    end)
  end

  # ---------- boards and cards ----------

  def handle_event("open_board", %{"repo" => repo}, socket) do
    repo = String.trim(repo)

    socket
    |> assign(dialog: nil)
    |> outcome(OwnerActions.open_board(repo), fn -> "Board <b>#{esc(repo)}</b> opened" end)
  end

  def handle_event("queue_card", %{"repo" => repo, "number" => n} = p, socket) do
    ref = repo <> "#" <> String.trim(n)

    socket
    |> assign(dialog: nil)
    |> outcome(OwnerActions.queue_card(Map.put(p, "issue_ref", ref)), fn ->
      "<b>#{esc(ref)}</b> queued"
    end)
  end

  def handle_event("rerank", p, socket) do
    move = %{
      card_id: p["card_id"],
      after_id: p["after_card_id"],
      before_id: p["before_card_id"],
      group: p["group"]
    }

    case OwnerActions.rerank(move, fresh_cards(), p["view"] || socket.assigns.nav["view"]) do
      {:ok, done} ->
        {:noreply, socket |> toast(rank_toast(socket, done)) |> load()}

      {:error, reason} ->
        {:noreply, socket |> refused(reason, label(socket, move.card_id)) |> load()}
    end
  end

  def handle_event("rationale", %{"toast" => toast_id, "text" => text}, socket) do
    case Enum.find(socket.assigns.toasts, &(&1.id == toast_id)) do
      %{card_id: id, rank: rank} ->
        socket
        |> drop_toast(toast_id)
        |> outcome(OwnerActions.rank_at(id, rank, text), fn ->
          "Reason kept for #{label(socket, id)}"
        end)

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("undo", %{"toast" => toast_id}, socket) do
    case Enum.find(socket.assigns.toasts, &(&1.id == toast_id)) do
      %{undo: undo} ->
        socket
        |> drop_toast(toast_id)
        |> outcome(OwnerActions.restore(undo), fn -> "Moved back" end)

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("pin", %{"card_id" => id}, socket) do
    card = Enum.find(fresh_cards(), &(&1.card_id == id))

    case card && OwnerActions.toggle_pin(card) do
      {:ok, :pinned} ->
        {:noreply,
         socket
         |> toast(
           info(
             "#{label(socket, id)} <b>pinned</b> at rank #{card.rank}. The prioritiser cannot move it."
           )
         )
         |> load()}

      {:ok, :unpinned} ->
        {:noreply,
         socket
         |> toast(
           info("#{label(socket, id)} <b>unpinned</b>. The prioritiser may rank it again.")
         )
         |> load()}

      {:error, reason} ->
        {:noreply, refused(socket, reason, label(socket, id))}

      nil ->
        {:noreply, refused(socket, :unknown_card, nil)}
    end
  end

  def handle_event("pin_at", %{"card_id" => id, "rank" => rank}, socket) do
    case Integer.parse(String.trim(rank)) do
      {n, ""} ->
        outcome(socket, OwnerActions.rank_at(id, n), fn ->
          "#{label(socket, id)} <b>pinned</b> at rank #{n}"
        end)

      _ ->
        {:noreply, refused(socket, :invalid_rank, nil)}
    end
  end

  def handle_event(action, params, %{assigns: %{nav: %{"card" => id}}} = socket)
      when is_binary(id),
      do: card_action(action, id, params, socket)

  defp card_action("reserve", id, %{"lane" => ""}, socket),
    do: outcome(socket, OwnerActions.lift(id), fn -> "#{label(socket, id)} open to any agent" end)

  defp card_action("reserve", id, %{"lane" => lane}, socket),
    do:
      outcome(socket, OwnerActions.reserve(id, lane), fn ->
        "#{label(socket, id)} reserved for <b>#{esc(lane)}</b>"
      end)

  defp card_action("file", id, %{"package" => ""}, socket),
    do:
      outcome(socket, OwnerActions.unfile(id), fn -> "#{label(socket, id)} is in no package" end)

  defp card_action("file", id, %{"package" => ref}, socket),
    do:
      outcome(socket, OwnerActions.file(id, ref), fn ->
        "#{label(socket, id)} filed in <b>#{esc(ref)}</b>"
      end)

  defp card_action("reclassify", id, %{"kind" => kind}, socket),
    do:
      outcome(socket, OwnerActions.reclassify(id, kind), fn ->
        "#{label(socket, id)} is a <b>#{esc(kind)}</b>"
      end)

  defp card_action("unblock", id, _p, socket),
    do: outcome(socket, OwnerActions.unblock(id), fn -> "#{label(socket, id)} unblocked" end)

  defp card_action("comment", id, %{"text" => text}, socket),
    do:
      outcome(socket, OwnerActions.comment(id, text), fn ->
        "Comment posted as the <b>owner</b>"
      end)

  defp card_action("tag", id, %{"tag" => tag}, socket),
    do: outcome(socket, OwnerActions.tag(id, tag), fn -> "Tagged <b>#{esc(tag)}</b>" end)

  defp card_action("untag", id, %{"tag" => tag}, socket),
    do: outcome(socket, OwnerActions.untag(id, tag), fn -> "Tag <b>#{esc(tag)}</b> removed" end)

  defp card_action("reason", id, %{"action" => action, "reason" => reason}, socket) do
    socket
    |> assign(dialog: nil)
    |> outcome(reasoned(action, id, reason), fn -> "#{label(socket, id)} #{past(action)}" end)
  end

  defp card_action(_unknown, _id, _params, socket), do: {:noreply, socket}

  defp reasoned("release", id, reason), do: OwnerActions.release(id, reason)
  defp reasoned("block", id, reason), do: OwnerActions.block(id, reason)
  defp reasoned("withdraw", id, reason), do: OwnerActions.withdraw(id, reason)
  defp reasoned(_unknown, _id, _reason), do: {:error, :unknown_command}

  defp past("release"), do: "released to the queue"
  defp past("block"), do: "blocked"
  defp past("withdraw"), do: "withdrawn"
  defp past(_unknown), do: "changed"

  # ---------- helpers ----------

  # An action that depends on where cards are reads the ladder now, not the
  # copy this socket rendered last: a projection may have landed since.
  defp fresh_cards do
    %{packages: packages, loose: loose} = GetLadder.get_ladder()
    Enum.flat_map(packages, & &1.cards) ++ loose
  end

  defp outcome(socket, :ok, message), do: {:noreply, socket |> toast(info(message.())) |> load()}
  defp outcome(socket, {:error, reason}, _message), do: {:noreply, refused(socket, reason, nil)}

  defp refused(socket, reason, subject) do
    %{reason: code, text: text, fix: fix} = OwnerActions.explain(reason)

    toast(socket, %{
      type: :err,
      reason: code,
      text: Enum.join(Enum.reject([subject, text], &is_nil/1), " "),
      fix: fix
    })
  end

  defp info(html), do: %{type: :info, html: html}

  defp toast(socket, t) do
    t = Map.put(t, :id, "t" <> Integer.to_string(System.unique_integer([:positive])))
    update(socket, :toasts, &Enum.take(&1 ++ [t], -4))
  end

  defp drop_toast(socket, id),
    do: update(socket, :toasts, &Enum.reject(&1, fn t -> t.id == id end))

  defp rank_toast(socket, %{card_id: id, rank: rank, moved_to: moved, undo: undo}) do
    %{
      type: :rank,
      card_id: id,
      rank: rank,
      label: label(socket, id),
      moved_to: moved,
      undo: undoable(undo)
    }
  end

  defp undoable(undo), do: undo

  defp label(socket, id) do
    case Map.get(socket.assigns.by_id, id) do
      %{issue_ref: ref} -> "<b>#{esc(short_ref(ref))}</b>"
      nil -> nil
    end
  end

  defp enlisted(%{"name" => name, "role" => role}) when role in ["supervisor", "prioritiser"],
    do:
      "<b>#{esc(name)}</b> enlisted and appointed #{role}. Ask it to call <b>claim_next_card</b>."

  defp enlisted(%{"name" => name}),
    do: "<b>#{esc(name)}</b> enlisted. Ask it to call <b>claim_next_card</b>."

  defp dialog("reason", p), do: {:reason, p["action"]}
  defp dialog("reserve_for", p), do: {:reserve_for, p["name"]}

  defp dialog(name, _p) when name in ~w(enlist open_board queue help),
    do: String.to_existing_atom(name)

  defp patch(socket, changes) do
    nav = Map.merge(socket.assigns.nav, changes)

    query =
      for k <- @params, v = nav[k], v not in [nil, ""], v != @defaults[k], do: {k, v}

    push_patch(socket, to: "/" <> query_string(query))
  end

  defp query_string([]), do: ""
  defp query_string(query), do: "?" <> URI.encode_query(query)

  defp toggle(same, same), do: nil
  defp toggle(_old, new), do: new

  defp toggle_member(set, key),
    do: if(MapSet.member?(set, key), do: MapSet.delete(set, key), else: MapSet.put(set, key))

  @hex ~r/^[0-9a-fA-F]*$/

  defp enlist_hints(params, crew \\ []) do
    name = String.trim(params["name"] || "")
    node = String.trim(params["node_id"] || "")
    taken = Enum.find(crew, &(String.downcase(&1.name) == String.downcase(name) and name != ""))
    known = Enum.find(crew, &(&1.node_id == String.downcase(node)))

    %{
      name: name_hint(name, taken),
      node: node_hint(node, Regex.match?(@hex, node), known),
      ok:
        name != "" and taken == nil and known == nil and String.length(node) == 64 and
          Regex.match?(@hex, node)
    }
  end

  defp name_hint("", _), do: {:neutral, "Starts with a letter: letters, digits, - and _"}
  defp name_hint(name, nil), do: name_ok(Regex.match?(~r/^[A-Za-z][A-Za-z0-9_-]{0,39}$/, name))
  defp name_hint(name, _taken), do: {:bad, "Another agent is called #{name}"}

  defp name_ok(true), do: {:ok, "Looks good"}
  defp name_ok(false), do: {:bad, "Starts with a letter: letters, digits, - and _"}

  defp node_hint("", _hex, _known), do: {:neutral, "Waiting for a node id"}
  defp node_hint(_node, _hex, %{name: name}), do: {:bad, "Already enlisted as #{name}"}

  defp node_hint(node, true, nil) when byte_size(node) == 64,
    do: {:ok, "Looks like a node id: " <> String.slice(node, 0, 12) <> "…"}

  defp node_hint(node, hex, nil),
    do:
      {:bad,
       "#{String.length(node)} of 64 hex characters" <>
         if(hex, do: "", else: ", and only 0-9 a-f")}

  @impl true
  def render(assigns), do: ladder_page(assigns)
end
