defmodule MclKanban.GetCrew.GetCrewResponder do
  # mcl-kanban/get_crew: no arguments. Every crew with its operator and its
  # agents (#28, the answer #13 asked to have advertised). Enlisted agents only,
  # like every other read.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias MclKanban.Wire
  alias QueryBoards.GetCrew.GetCrew

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply = with {:ok, _by} <- Actor.of_caller(payload), do: {:ok, %{crews: crews()}}
    {:reply, Wire.reply(reply), state}
  end

  defp crews, do: Enum.map(GetCrew.get_crew(), &Wire.crew/1)
end
