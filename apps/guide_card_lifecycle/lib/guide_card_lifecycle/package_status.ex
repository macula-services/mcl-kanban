defmodule GuideCardLifecycle.PackageStatus do
  # A work package's status, bit flags: OPENED 1, PINNED 2.
  @moduledoc false

  def opened, do: 1
  def pinned, do: 2
end
