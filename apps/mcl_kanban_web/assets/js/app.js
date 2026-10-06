import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, { params: { _csrf_token: csrfToken } });
liveSocket.connect();
window.liveSocket = liveSocket;

// Light or dark: the system's choice until the owner picks one.
const root = document.documentElement;
const saved = (() => { try { return localStorage.getItem("mkb-theme"); } catch (_) { return null; } })();
if (saved) root.dataset.theme = saved;
document.addEventListener("click", (e) => {
  if (!e.target.closest("[data-theme-toggle]")) return;
  const dark = root.dataset.theme ? root.dataset.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
  root.dataset.theme = dark ? "light" : "dark";
  try { localStorage.setItem("mkb-theme", root.dataset.theme); } catch (_) {}
});

// Keyboard: n queues a card, Esc closes the drawer.
document.addEventListener("keydown", (e) => {
  const typing = ["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement?.tagName);
  if (e.key === "Escape") { document.querySelector("[data-close-drawer]")?.click(); return; }
  if (typing || e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === "n") {
    const field = document.querySelector("[data-shortcut='n']");
    if (field) { e.preventDefault(); field.closest("details")?.setAttribute("open", ""); field.focus(); }
  }
});
