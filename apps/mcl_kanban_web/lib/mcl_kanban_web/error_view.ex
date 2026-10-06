defmodule MclKanbanWeb.ErrorView do
  # A clean 404/500 instead of a raw crash page.
  @moduledoc false

  def render("404.html", _assigns), do: page("Nothing here", "This page does not exist.")

  def render("500.html", _assigns),
    do: page("Something broke", "The board hit an error. Reload to try again.")

  def render(_template, _assigns), do: page("Error", "Something went wrong.")

  defp page(title, message) do
    {:safe,
     """
     <!doctype html><html lang="en"><head><meta charset="utf-8">
     <meta name="viewport" content="width=device-width, initial-scale=1">
     <title>#{title} · mcl-kanban</title>
     <style>body{font-family:system-ui,sans-serif;display:grid;place-items:center;height:100vh;margin:0;background:#f6f7f9;color:#1d2433}
     a{color:#2463eb}@media (prefers-color-scheme:dark){body{background:#12151c;color:#e6e9ef}a{color:#7aa2ff}}</style>
     </head><body><main><h1>#{title}</h1><p>#{message}</p><p><a href="/">Back to the boards</a></p></main></body></html>
     """}
  end
end
