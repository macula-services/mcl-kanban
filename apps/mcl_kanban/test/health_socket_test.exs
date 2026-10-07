defmodule MclKanban.HealthSocketTest do
  # /health is a Unix socket inside the container, not a port (mcl_om 0.39,
  # #23): no service listens on a port just to be health-checked.
  use ExUnit.Case, async: true

  @root Path.expand("../../..", __DIR__)
  @socket "/run/mcl/health.sock"

  test "mcl_om serves /health on the socket, and no health port is configured" do
    assert Application.fetch_env!(:mcl_om, :health_socket) == @socket
    refute File.read!(Path.join(@root, "config/runtime.exs")) =~ "health_port"
  end

  test "the image checks health over the socket and exposes no health port" do
    containerfile = File.read!(Path.join(@root, "Containerfile"))
    assert containerfile =~ "--unix-socket #{@socket}"
    refute containerfile =~ "MCL_HEALTH_PORT"
    refute containerfile =~ ~r/EXPOSE .*8492/
  end
end
