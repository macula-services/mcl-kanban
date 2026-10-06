defmodule MclKanbanWeb.Endpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :mcl_kanban_web

  @session_options [
    store: :cookie,
    key: "_mcl_kanban_key",
    signing_salt: "mkb_session_salt",
    same_site: "Strict"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Static, at: "/", from: :mcl_kanban_web, gzip: false, only: ~w(assets))
  plug(Plug.RequestId)
  plug(Plug.Session, @session_options)
  plug(MclKanbanWeb.Router)
end
