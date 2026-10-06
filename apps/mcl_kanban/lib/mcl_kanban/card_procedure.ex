defmodule MclKanban.CardProcedure do
  # The mesh face of a card command, the same for every card procedure: the
  # caller is who the crew says the signed node id is (Actor.of_caller/1),
  # the command is built from the arguments plus that actor, the desk
  # dispatches it, and the reply is the card as its own event left it.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias MclKanban.Wire

  @spec call(map(), module(), module(), map()) :: map()
  def call(payload, command, desk, args) do
    Wire.reply(
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, cmd} <- command.new(Map.put(args, :by, by)),
           {:ok, version, _events} <- desk.dispatch(cmd),
           do: Wire.card_after(cmd.card_id, version)
    )
  end
end
