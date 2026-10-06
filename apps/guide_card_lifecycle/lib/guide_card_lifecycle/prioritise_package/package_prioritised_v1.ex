defmodule GuideCardLifecycle.PrioritisePackage.PackagePrioritisedV1 do
  # Event: package_prioritised_v1.
  @moduledoc false

  alias GuideCardLifecycle.PackageEvent

  def event_type, do: "package_prioritised_v1"

  def new(cmd, package, status),
    do:
      PackageEvent.new(event_type(), cmd.package_id, cmd.by, status, %{
        issue_ref: package.issue_ref,
        rank: cmd.rank,
        rationale: cmd.rationale
      })
end
