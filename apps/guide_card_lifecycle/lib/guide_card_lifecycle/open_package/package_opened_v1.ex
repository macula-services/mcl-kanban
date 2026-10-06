defmodule GuideCardLifecycle.OpenPackage.PackageOpenedV1 do
  # Event: package_opened_v1.
  @moduledoc false

  alias GuideCardLifecycle.PackageEvent

  def event_type, do: "package_opened_v1"

  def new(cmd, status),
    do:
      PackageEvent.new(event_type(), cmd.package_id, cmd.by, status, %{
        issue_ref: cmd.issue_ref,
        title: cmd.title
      })
end
