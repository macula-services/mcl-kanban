defmodule GuideCardLifecycle.BoardStatus do
  # A board's status, bit flags.
  @moduledoc false

  def opened, do: 1
  def archived, do: 2
end
