defmodule ProjectBoards.BoardsChanged do
  # The pubsub seam: after every write the projection says what changed, on
  # one topic. The LiveViews subscribe and re-read; they never derive business
  # meaning from the message.
  @moduledoc false

  @topic "boards:changed"

  def topic, do: @topic

  def broadcast(event_type, data) do
    :ok =
      Phoenix.PubSub.broadcast(MclKanbanWeb.PubSub, @topic, {
        :boards_changed,
        %{event_type: event_type, card_id: data[:card_id], board_id: data[:board_id]}
      })
  end
end
