defmodule GuideCardLifecycle.OpenPackage.MaybeOpenPackage do
  # Handler: the supervisor, the operator or the owner opens a work package,
  # once. The package belongs to its repo's board's home crew (#29): the
  # board must be open, and only that crew (or the owner) opens it.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, BoardAggregate, BoardState, PackageAggregate, PackageState}
  alias GuideCardLifecycle.{CrewName, PackageStatus}
  alias GuideCardLifecycle.OpenPackage.{OpenPackageV1, PackageOpenedV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(OpenPackageV1, payload))

  def handle(%PackageState{} = package, %OpenPackageV1{} = cmd) do
    cond do
      refusal = Actor.refused(cmd.by, @who, CrewName.home_crew_in(cmd)) -> {:error, refusal}
      PackageState.open?(package) -> {:error, :already_open}
      true -> {:ok, [PackageOpenedV1.new(cmd, PackageStatus.opened())]}
    end
  end

  def dispatch(%OpenPackageV1{} = cmd),
    do: opened(BoardAggregate.current(cmd.board_id), cmd)

  defp opened(board, cmd), do: opened_on(BoardState.open?(board), board, cmd)

  defp opened_on(false, _board, _cmd), do: {:error, :unknown_board}

  defp opened_on(true, board, cmd) do
    cmd = %{cmd | home_crew: board.home_crew}
    PackageAggregate.dispatch(:open_package, cmd.package_id, OpenPackageV1.to_map(cmd))
  end
end
