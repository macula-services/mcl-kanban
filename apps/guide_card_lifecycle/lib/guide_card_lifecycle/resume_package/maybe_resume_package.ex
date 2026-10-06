defmodule GuideCardLifecycle.ResumePackage.MaybeResumePackage do
  # Handler: the prioritiser or the owner resumes a paused package (#17). Its
  # cards are handed out again; the package comes back unranked.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, PackageAggregate, PackageState, PackageStatus}
  alias GuideCardLifecycle.ResumePackage.{PackageResumedV1, ResumePackageV1}

  @who [:prioritiser, :owner]

  def handle_payload(state, payload), do: handle(state, struct(ResumePackageV1, payload))

  def handle(%PackageState{} = package, %ResumePackageV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) ->
        {:error, :not_permitted}

      not PackageState.deferred?(package) ->
        {:error, :not_deferred}

      true ->
        {:ok,
         [
           PackageResumedV1.new(
             cmd,
             package,
             :evoq_bit_flags.unset(package.status, PackageStatus.deferred())
           )
         ]}
    end
  end

  def dispatch(%ResumePackageV1{} = cmd),
    do: PackageAggregate.dispatch(:resume_package, cmd.package_id, ResumePackageV1.to_map(cmd))
end
