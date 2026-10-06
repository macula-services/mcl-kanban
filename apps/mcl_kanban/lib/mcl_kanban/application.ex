defmodule MclKanban.Application do
  # Opens this service's own store and its evoq subscription
  # (MclKanban.EventStore, from MclKanban.Service.event_store/0), THEN lets
  # mcl_om:boot/1 wire the mesh, the realm identity and health, advertise the
  # procedures and start the service. The departments are runtime deps of
  # this app, so their projections are registered before the subscription
  # delivers.
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :ok = MclKanban.EventStore.open(MclKanban.Service.event_store())
    :mcl_om.boot(MclKanban.Service)
  end
end
