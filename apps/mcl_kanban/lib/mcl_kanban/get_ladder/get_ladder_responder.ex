defmodule MclKanban.GetLadder.GetLadderResponder do
  # mcl-kanban/get_ladder: no arguments. Every work package in rank order with its cards in rank order, and the loose cards. Enlisted agents only.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias MclKanban.Wire
  alias QueryBoards.GetLadder.GetLadder

  @package_fields ~w(package_id issue_ref title rank pinned ranked_by rationale repos)a

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply = with {:ok, _by} <- Actor.of_caller(payload), do: read()
    {:reply, Wire.reply(reply), state}
  end

  defp read do
    %{packages: packages, loose: loose} = GetLadder.get_ladder()

    {:ok,
     %{
       packages: Enum.map(packages, &package/1),
       loose: Enum.map(loose, &Wire.card/1)
     }}
  end

  defp package(p),
    do: p |> Map.take(@package_fields) |> Map.put(:cards, Enum.map(p.cards, &Wire.card/1))
end
