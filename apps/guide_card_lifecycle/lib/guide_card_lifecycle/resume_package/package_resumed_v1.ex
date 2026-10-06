defmodule GuideCardLifecycle.ResumePackage.PackageResumedV1 do
  # Event: package_resumed_v1.
  @moduledoc false

  alias GuideCardLifecycle.PackageEvent

  def event_type, do: "package_resumed_v1"

  def new(cmd, package, status, fields \\ %{}),
    do:
      PackageEvent.new(
        event_type(),
        cmd.package_id,
        cmd.by,
        status,
        Map.put(fields, :issue_ref, package.issue_ref)
      )
end
