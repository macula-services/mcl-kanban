defmodule GuideCardLifecycle.PackageStatus do
  # A work package's status, bit flags: OPENED 1, PINNED 2, DEFERRED 4 (#17).
  @moduledoc false

  def opened, do: 1
  def pinned, do: 2
  def deferred, do: 4
end
