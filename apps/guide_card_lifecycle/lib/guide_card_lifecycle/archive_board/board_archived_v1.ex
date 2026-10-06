defmodule GuideCardLifecycle.ArchiveBoard.BoardArchivedV1 do
  # Event: board_archived_v1.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.ArchiveBoard.ArchiveBoardV1

  def event_type, do: "board_archived_v1"

  def from_command(%ArchiveBoardV1{} = cmd) do
    Map.merge(Actor.record(cmd.by), %{
      event_type: event_type(),
      board_id: cmd.board_id,
      repo: cmd.repo,
      at: System.system_time(:millisecond)
    })
  end
end
