defmodule MclKanbanWeb.OwnerOnlyOnLoopbackTest do
  # The UI acts as the owner, so only the box's loopback may drive it: the
  # socket refuses any Origin but the local ones (a page on another name,
  # rebound to 127.0.0.1, must not get the owner), and the image binds the
  # UI to loopback by default.
  use ExUnit.Case, async: true

  import Plug.Test

  alias Phoenix.Socket.Transport

  defp from(origin) do
    :get
    |> conn("/live/websocket")
    |> Plug.Conn.put_req_header("origin", origin)
    |> Transport.check_origin(Phoenix.LiveView.Socket, MclKanbanWeb.Endpoint, [], & &1)
  end

  test "a local origin opens the socket" do
    port = MclKanbanWeb.Endpoint.config(:http)[:port]

    for host <- ["localhost", "127.0.0.1", "[::1]"] do
      refute from("http://#{host}:#{port}").halted, host
    end
  end

  test "any other origin is refused, including a name rebound to loopback" do
    port = MclKanbanWeb.Endpoint.config(:http)[:port]

    for origin <- ["http://attacker.example:#{port}", "http://box.example:#{port}", "null"] do
      conn = from(origin)
      assert conn.halted, origin
      assert conn.status == 403, origin
    end
  end

  test "the image binds the UI to loopback unless the box says otherwise" do
    containerfile = File.read!(Path.expand("../../../Containerfile", __DIR__))
    assert containerfile =~ ~r/^ENV MCL_HTTP_IP=127\.0\.0\.1$/m
    refute containerfile =~ "MCL_HTTP_IP=0.0.0.0"
  end
end
