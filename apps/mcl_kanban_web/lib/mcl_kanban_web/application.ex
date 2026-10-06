defmodule MclKanbanWeb.Application do
  # Starts only the Endpoint. The MclKanbanWeb.PubSub registry belongs to
  # project_boards (the writer side), which starts first.
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args),
    do:
      Supervisor.start_link([MclKanbanWeb.Endpoint],
        strategy: :one_for_one,
        name: MclKanbanWeb.Supervisor
      )

  @impl true
  def config_change(changed, _new, removed) do
    MclKanbanWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
