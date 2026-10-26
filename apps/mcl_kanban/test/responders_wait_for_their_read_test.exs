defmodule MclKanban.RespondersWaitForTheirReadTest do
  # A responder that dispatches a command may not reply straight from it: the
  # caller's next read would miss its own write (#37). This lists every
  # responder that dispatches without reaching a read that waits for the
  # projection to hold the write.
  use ExUnit.Case, async: true

  @dir Path.expand("../lib/mcl_kanban", __DIR__)

  # CardProcedure.call/4 dispatches and replies Wire.card_after/2, which waits
  # for the card at the command's own version: a card desk gets its await by
  # going through it.
  @waits ["await_", "await(", "Wire.card_after", "Wire.once_read", "CardProcedure.call"]

  test "every responder that dispatches a command waits for its read model" do
    assert offenders() == [],
           "these responders reply without waiting for their read model: #{inspect(offenders())}"
  end

  test "the check sees a desk that would reply from the command alone" do
    replies_alone = """
    defmodule X do
      def handle_request(payload, state) do
        with {:ok, _version, _events} <- MaybeX.dispatch(cmd),
             do: {:ok, %{card_id: cmd.card_id}}
      end
    end
    """

    waits = """
    defmodule X do
      def handle_request(payload, state) do
        with {:ok, _version, _events} <- MaybeX.dispatch(cmd),
             :ok <- GetCrew.await_agent(cmd.node_id, cmd.name),
             do: {:ok, %{agent: cmd.name}}
      end
    end
    """

    assert dispatches?(replies_alone)
    refute waits?(replies_alone)
    assert waits?(waits)
  end

  defp offenders do
    @dir
    |> Path.join("*/*_responder.ex")
    |> Path.wildcard()
    |> Enum.filter(fn file ->
      source = File.read!(file)
      dispatches?(source) and not waits?(source)
    end)
    |> Enum.map(&(&1 |> Path.dirname() |> Path.basename()))
    |> Enum.sort()
  end

  defp dispatches?(source), do: String.contains?(source, ".dispatch(")

  defp waits?(source), do: Enum.any?(@waits, &String.contains?(source, &1))
end
