defmodule MclKanbanWeb.BuildInfo do
  # The git commit in the asset URL (?v=<sha>), so a redeploy is a new URL and
  # never yesterday's cached bundle. Read once, at compile time.
  @moduledoc false

  @asset_version System.get_env("GIT_SHA", "dev") |> String.slice(0, 12)

  def asset_version, do: @asset_version
end
