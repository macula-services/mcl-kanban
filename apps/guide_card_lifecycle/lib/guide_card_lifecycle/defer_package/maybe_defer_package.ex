defmodule GuideCardLifecycle.DeferPackage.MaybeDeferPackage do
  # Handler: the prioritiser or the owner pauses an open package (#17). Its
  # cards stay queued and are not handed out until it is resumed. A paused
  # package is not a contender, so deferring clears its rank and its pin.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, PackageAggregate, PackageState, PackageStatus}
  alias GuideCardLifecycle.DeferPackage.{DeferPackageV1, PackageDeferredV1}

  @who [:prioritiser, :owner]

  def handle_payload(state, payload), do: handle(state, struct(DeferPackageV1, payload))

  def handle(%PackageState{} = package, %DeferPackageV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) ->
        {:error, :not_permitted}

      not PackageState.open?(package) ->
        {:error, :unknown_package}

      PackageState.deferred?(package) ->
        {:error, :already_deferred}

      true ->
        {:ok,
         [
           PackageDeferredV1.new(cmd, package, deferred(package.status), %{
             reason: cmd.reason,
             rank: nil
           })
         ]}
    end
  end

  defp deferred(status),
    do:
      status
      |> :evoq_bit_flags.unset(PackageStatus.pinned())
      |> :evoq_bit_flags.set(PackageStatus.deferred())

  def dispatch(%DeferPackageV1{} = cmd),
    do: PackageAggregate.dispatch(:defer_package, cmd.package_id, DeferPackageV1.to_map(cmd))
end
