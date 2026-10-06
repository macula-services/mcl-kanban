defmodule GuideCardLifecycle.OpenPackage.MaybeOpenPackage do
  # Handler: the supervisor or the owner opens a work package, once.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, PackageAggregate, PackageState, PackageStatus}
  alias GuideCardLifecycle.OpenPackage.{OpenPackageV1, PackageOpenedV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(OpenPackageV1, payload))

  def handle(%PackageState{} = package, %OpenPackageV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      PackageState.open?(package) -> {:error, :already_open}
      true -> {:ok, [PackageOpenedV1.new(cmd, PackageStatus.opened())]}
    end
  end

  def dispatch(%OpenPackageV1{} = cmd),
    do: PackageAggregate.dispatch(:open_package, cmd.package_id, OpenPackageV1.to_map(cmd))
end
