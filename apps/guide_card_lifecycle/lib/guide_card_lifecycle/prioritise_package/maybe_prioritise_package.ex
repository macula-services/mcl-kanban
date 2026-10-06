defmodule GuideCardLifecycle.PrioritisePackage.MaybePrioritisePackage do
  # Handler: the prioritiser or the owner ranks an open package. An owner
  # rank PINS it: the prioritiser cannot change it until the owner unpins.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, PackageAggregate, PackageState, PackageStatus}
  alias GuideCardLifecycle.PrioritisePackage.{PackagePrioritisedV1, PrioritisePackageV1}

  @who [:prioritiser, :owner]

  def handle_payload(state, payload), do: handle(state, struct(PrioritisePackageV1, payload))

  def handle(%PackageState{} = package, %PrioritisePackageV1{by: by} = cmd) do
    cond do
      not Actor.allowed?(by, @who) -> {:error, :not_permitted}
      not PackageState.open?(package) -> {:error, :unknown_package}
      PackageState.deferred?(package) -> {:error, :deferred}
      PackageState.pinned?(package) and by.kind != :owner -> {:error, :pinned_by_owner}
      true -> {:ok, [PackagePrioritisedV1.new(cmd, package, pinned(package.status, by))]}
    end
  end

  defp pinned(status, %Actor{kind: :owner}),
    do: :evoq_bit_flags.set(status, PackageStatus.pinned())

  defp pinned(status, %Actor{}), do: status

  def dispatch(%PrioritisePackageV1{} = cmd),
    do:
      PackageAggregate.dispatch(
        :prioritise_package,
        cmd.package_id,
        PrioritisePackageV1.to_map(cmd)
      )
end
