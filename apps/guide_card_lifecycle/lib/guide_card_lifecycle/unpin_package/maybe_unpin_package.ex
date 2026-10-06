defmodule GuideCardLifecycle.UnpinPackage.MaybeUnpinPackage do
  # Handler: only the owner unpins, and only a pinned package.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, PackageAggregate, PackageState, PackageStatus}
  alias GuideCardLifecycle.UnpinPackage.{PackageUnpinnedV1, UnpinPackageV1}

  @who [:owner]

  def handle_payload(state, payload), do: handle(state, struct(UnpinPackageV1, payload))

  def handle(%PackageState{} = package, %UnpinPackageV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) ->
        {:error, :not_permitted}

      not PackageState.pinned?(package) ->
        {:error, :not_pinned}

      true ->
        {:ok,
         [
           PackageUnpinnedV1.new(
             cmd,
             package,
             :evoq_bit_flags.unset(package.status, PackageStatus.pinned())
           )
         ]}
    end
  end

  def dispatch(%UnpinPackageV1{} = cmd),
    do: PackageAggregate.dispatch(:unpin_package, cmd.package_id, UnpinPackageV1.to_map(cmd))
end
