defmodule MclKanban.HealthSocketTest do
  # /health is a Unix socket, not a port (mcl_om 0.39, #23): no service
  # listens on a port just to be health-checked. In the release that socket is
  # /run/mcl/health.sock, which the container's HEALTHCHECK reaches with
  # curl --unix-socket; a test run takes a socket in its own data dir, because
  # /run belongs to root and the suite runs as whoever checked the tree out.
  use ExUnit.Case, async: true

  @root Path.expand("../../..", __DIR__)
  @release_socket "/run/mcl/health.sock"

  test "a test run serves /health on a socket in its own data dir, and no health port" do
    socket = Application.fetch_env!(:mcl_om, :health_socket)
    dir = System.fetch_env!("MCL_DATA_DIR")

    assert Path.dirname(socket) == dir
    assert Path.basename(socket) == "health.sock"

    runtime = File.read!(Path.join(@root, "config/runtime.exs"))
    assert runtime =~ "MCL_HEALTH_SOCKET"
    assert runtime =~ ~s("#{@release_socket}")
    refute runtime =~ "health_port"
  end

  test "the image checks health over the socket and exposes no health port" do
    containerfile = File.read!(Path.join(@root, "Containerfile"))
    assert containerfile =~ "--unix-socket #{@release_socket}"
    refute containerfile =~ "MCL_HEALTH_PORT"
    refute containerfile =~ ~r/EXPOSE .*8492/
  end
end
