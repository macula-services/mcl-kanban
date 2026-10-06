defmodule GuideCardLifecycle.OpenBoard.BoardOpenedV1 do
  # Event: board_opened_v1.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.OpenBoard.OpenBoardV1

  def event_type, do: "board_opened_v1"

  def from_command(%OpenBoardV1{} = cmd) do
    Map.merge(Actor.record(cmd.by), %{
      event_type: event_type(),
      board_id: cmd.board_id,
      repo: cmd.repo,
      at: System.system_time(:millisecond)
    })
  end
end
