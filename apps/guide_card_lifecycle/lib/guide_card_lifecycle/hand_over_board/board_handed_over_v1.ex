defmodule GuideCardLifecycle.HandOverBoard.BoardHandedOverV1 do
  # Event: board_handed_over_v1, naming the board's new home crew.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.HandOverBoard.HandOverBoardV1

  def event_type, do: "board_handed_over_v1"

  def from_command(%HandOverBoardV1{} = cmd, from_crew) do
    Map.merge(Actor.record(cmd.by), %{
      event_type: event_type(),
      board_id: cmd.board_id,
      repo: cmd.repo,
      home_crew: cmd.crew,
      from_crew: from_crew,
      at: System.system_time(:millisecond)
    })
  end
end
