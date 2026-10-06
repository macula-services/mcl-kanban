defmodule GuideCardLifecycle.ResumeBoard.BoardResumedV1 do
  # Event: board_resumed_v1.
  @moduledoc false

  alias GuideCardLifecycle.Actor

  def event_type, do: "board_resumed_v1"

  def from_command(cmd, fields \\ %{}) do
    cmd.by
    |> Actor.record()
    |> Map.merge(%{
      event_type: event_type(),
      board_id: cmd.board_id,
      repo: cmd.repo,
      at: System.system_time(:millisecond)
    })
    |> Map.merge(fields)
  end
end
