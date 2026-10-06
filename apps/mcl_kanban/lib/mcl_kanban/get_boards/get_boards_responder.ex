defmodule MclKanban.GetBoards.GetBoardsResponder do
  # mcl-kanban/get_boards: no arguments. Every board, with its column counts. Enlisted agents only.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias MclKanban.Wire
  alias QueryBoards.GetBoards.GetBoards

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply = with {:ok, by} <- Actor.of_caller(payload), do: read(by, payload)
    {:reply, Wire.reply(reply), state}
  end

  defp read(_by, _payload), do: {:ok, %{boards: GetBoards.get_boards()}}
end
