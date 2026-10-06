defmodule GuideCardLifecycle.BoardStatus do
  # A board's status, bit flags: OPENED 1, ARCHIVED 2, DEFERRED 4 (#17: its
  # repo is paused).
  @moduledoc false

  def opened, do: 1
  def archived, do: 2
  def deferred, do: 4
end
