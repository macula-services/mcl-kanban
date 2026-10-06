import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";

// The owner's ladder (#9): keys, drag to re-rank, toasts, dialogs and the
// "new since you looked" comment dot. The server owns the ladder; these hooks
// only move what the owner moved and tell the server.

const root = document.documentElement;
const store = {
  get(k) { try { return localStorage.getItem(k); } catch (_) { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch (_) {} },
};

// Light or dark: the system's choice until the owner picks one.
const savedTheme = store.get("mkb-theme");
if (savedTheme) root.dataset.theme = savedTheme;
document.addEventListener("click", (e) => {
  if (!e.target.closest("[data-theme-toggle]")) return;
  const dark = root.dataset.theme ? root.dataset.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
  root.dataset.theme = dark ? "light" : "dark";
  store.set("mkb-theme", root.dataset.theme);
});

const cards = () => [...document.querySelectorAll("#ladder .card")];
const selected = () => document.querySelector('#ladder .card[aria-selected="true"]');
const view = () => document.getElementById("ladder")?.dataset.view || "pkg";

// After the owner moved a card in the DOM: its neighbours in its group and
// the group, which is all the server needs to place it with one rank.
function placed(li) {
  const prev = li.previousElementSibling, next = li.nextElementSibling;
  return {
    card_id: li.dataset.cardId,
    after_card_id: prev ? prev.dataset.cardId : null,
    before_card_id: next ? next.dataset.cardId : null,
    group: li.closest("section.pkg").dataset.key,
    view: view(),
  };
}

function flash(li) { li.classList.remove("flash"); void li.offsetWidth; li.classList.add("flash"); }

// Move a card one place up or down the whole ladder (across groups too),
// optimistically, and tell the server.
function nudge(hook, id, dir) {
  const list = cards(), i = list.findIndex((li) => li.dataset.cardId === id), j = i + dir;
  if (i < 0 || j < 0 || j >= list.length) return;
  const li = list[i], target = list[j];
  if (dir < 0) target.before(li); else target.after(li);
  flash(li);
  hook.pushEvent("rerank", placed(li));
}

const Keys = {
  mounted() {
    this.onKey = (e) => {
      const typing = ["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement?.tagName);
      if (e.key === "Escape") {
        if (document.querySelector("dialog[open]")) return;
        if (typing) { document.activeElement.blur(); return; }
        if (document.querySelector("#toasts .toast")) { this.pushEvent("dismiss_last_toast", {}); return; }
        this.pushEvent("close", {});
        return;
      }
      if (typing || e.metaKey || e.ctrlKey || e.altKey || document.querySelector("dialog[open]")) return;
      const list = cards(), sel = selected(), i = list.indexOf(sel);
      const pick = (li) => { if (li) { this.pushEvent("select", { card: li.dataset.cardId }); li.scrollIntoView({ block: "nearest" }); } };
      const k = e.key;
      if (k === "/") { e.preventDefault(); document.getElementById("q")?.focus(); }
      else if (k === "1") this.pushEvent("view", { view: "pkg" });
      else if (k === "2") this.pushEvent("view", { view: "repo" });
      else if (k === "j" || (k === "ArrowDown" && !e.shiftKey)) { e.preventDefault(); pick(list[Math.min(i + 1, list.length - 1)] || list[0]); }
      else if (k === "k" || (k === "ArrowUp" && !e.shiftKey)) { e.preventDefault(); pick(list[Math.max(i - 1, 0)] || list[0]); }
      else if (k === "Enter" && sel) this.pushEvent("open", { card: sel.dataset.cardId });
      else if (k === "ArrowUp" && e.shiftKey && sel) { e.preventDefault(); nudge(this, sel.dataset.cardId, -1); }
      else if (k === "ArrowDown" && e.shiftKey && sel) { e.preventDefault(); nudge(this, sel.dataset.cardId, 1); }
      else if (k === "p" && sel) this.pushEvent("pin", { card_id: sel.dataset.cardId });
      else if (k === "b") this.pushEvent("filter", { filter: "blocked" });
      else if (k === "c" && document.getElementById("comment-text")) { e.preventDefault(); document.getElementById("comment-text").focus(); }
      else if (k === "n") { e.preventDefault(); this.pushEvent("open_dialog", { dialog: "queue" }); }
      else if (k === " " && sel) { e.preventDefault(); this.pushEvent("toggle_group", { key: sel.closest("section.pkg").dataset.key }); }
      else if (k === "?") this.pushEvent("open_dialog", { dialog: "help" });
    };
    // The drawer's ▲▼ move the open card like ⇧↑ ⇧↓ do.
    this.onClick = (e) => {
      const b = e.target.closest("[data-nudge]");
      if (b) nudge(this, b.dataset.cardId, Number(b.dataset.nudge));
    };
    document.addEventListener("keydown", this.onKey);
    document.addEventListener("click", this.onClick);
  },
  destroyed() {
    document.removeEventListener("keydown", this.onKey);
    document.removeEventListener("click", this.onClick);
  },
};

// Drag a card onto another: it lands above or below it (whichever half the
// pointer is in), optimistically; the server ranks and pins it.
const Ladder = {
  mounted() {
    let dragging = null;
    const clear = () => this.el.querySelectorAll(".drop-before,.drop-after").forEach((x) => x.classList.remove("drop-before", "drop-after"));
    this.el.addEventListener("dragstart", (e) => {
      const li = e.target.closest(".card"); if (!li) return;
      dragging = li; li.classList.add("dragging"); e.dataTransfer.effectAllowed = "move";
    });
    this.el.addEventListener("dragend", () => { dragging?.classList.remove("dragging"); dragging = null; clear(); });
    this.el.addEventListener("dragover", (e) => {
      const li = e.target.closest(".card"); if (!dragging || !li || li === dragging) return;
      e.preventDefault();
      const r = li.getBoundingClientRect(), before = e.clientY < r.top + r.height / 2;
      clear(); li.classList.add(before ? "drop-before" : "drop-after");
    });
    this.el.addEventListener("drop", (e) => {
      const li = e.target.closest(".card"); if (!dragging || !li || li === dragging) return;
      e.preventDefault();
      if (li.classList.contains("drop-before")) li.before(dragging); else li.after(dragging);
      clear(); flash(dragging);
      this.pushEvent("rerank", placed(dragging));
    });
    this.updated();
  },
  // A comment count above what the owner last saw gets the dot.
  updated() {
    this.el.querySelectorAll(".cmt[data-seen-card]").forEach((el) => {
      const seen = Number(store.get("mkb-seen:" + el.dataset.seenCard) || 0);
      el.classList.toggle("new", Number(el.dataset.n) > seen);
      el.title = el.dataset.n + " comments" + (Number(el.dataset.n) > seen ? ", new since you looked" : "");
    });
  },
};

// The open card's comments are seen.
const Seen = {
  mounted() { this.mark(); },
  updated() { this.mark(); },
  mark() { store.set("mkb-seen:" + this.el.dataset.seenCard, this.el.dataset.n); },
};

// A toast goes after 7 s, unless it asks for something (a reason) or has
// the owner's focus.
const Toast = {
  mounted() {
    if (this.el.dataset.sticky) { this.el.querySelector("input")?.focus(); return; }
    this.timer = setTimeout(() => this.pushEvent("dismiss_toast", { id: this.el.id }), 7000);
  },
  destroyed() { clearTimeout(this.timer); },
};

// A dialog the server rendered opens modal; Esc or the backdrop closes it
// and tells the server.
const Dialog = {
  mounted() {
    this.el.showModal();
    this.el.querySelector("input:not([type=hidden]),select")?.focus();
    this.el.addEventListener("close", () => this.pushEvent("close_dialog", {}));
    this.el.addEventListener("click", (e) => { if (e.target === this.el) this.el.close(); });
  },
};

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { Keys, Ladder, Seen, Toast, Dialog },
});
liveSocket.connect();
window.liveSocket = liveSocket;
