defmodule MclKanbanWeb.Router do
  @moduledoc false

  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:put_root_layout, html: {MclKanbanWeb.Layouts, :root})
  end

  scope "/", MclKanbanWeb do
    pipe_through(:browser)

    live("/", OverviewLive)
    live("/boards/:owner/:name", BoardLive)
  end
end
