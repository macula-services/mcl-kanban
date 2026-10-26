defmodule MclKanban.RespondersWaitForTheirReadTest do
  # A responder that dispatches a command may not reply straight from it: the
  # caller's next read would miss its own write (#37). This reads each
  # responder's syntax tree — so a comment cannot satisfy it and a `Task.await`
  # cannot stand in for a read — and lists every responder that dispatches
  # before it waits.
  use ExUnit.Case, async: true

  @dir Path.expand("../lib/mcl_kanban", __DIR__)
  @card_procedure Path.join(@dir, "card_procedure.ex")

  test "every responder that dispatches a command waits for its read model" do
    files = responder_files()

    offenders =
      for file <- files, not waits_after_dispatch?(File.read!(file)), do: desk(file)

    assert offenders == [],
           "these responders reply without waiting for their read model: #{inspect(offenders)}"

    assert files != [], "no responder found under #{@dir}"
  end

  # Every card desk goes through this one face, so its wait is the one that
  # keeps them all honest: if it stopped reading the card first, every card
  # desk would reply from the command alone. It counts only if it dispatches,
  # and only with the wait after the dispatch.
  test "the card desk's shared face still dispatches and then waits for the card read" do
    source = File.read!(@card_procedure)
    assert dispatches?(source), "#{@card_procedure} dispatches nothing"
    assert waits_after_dispatch?(source)
  end

  test "the check reads the syntax tree, not the text" do
    # A comment naming a wait does not count.
    refute waits_after_dispatch?("""
           defmodule X do
             def handle_request(payload, state) do
               with {:ok, _v, _e} <- MaybeX.dispatch(cmd),
                    do: {:ok, %{card_id: cmd.card_id}}
               # no await_ needed here
             end
           end
           """)

    # Task.await and Task.await_many are not reads of this service's read model,
    # however they are spelled.
    for stray <- ["Task.await(task)", "Task.await_many(tasks)"] do
      refute waits_after_dispatch?("""
             defmodule X do
               def handle_request(payload, state) do
                 with {:ok, _v, _e} <- MaybeX.dispatch(cmd) do
                   #{stray}
                   {:ok, %{card_id: cmd.card_id}}
                 end
               end
             end
             """)
    end

    # A wait before the dispatch is not a wait for that dispatch.
    refute waits_after_dispatch?("""
           defmodule X do
             def handle_request(payload, state) do
               :ok = GetCrew.await_discharged(node_id)
               with {:ok, _v, _e} <- MaybeX.dispatch(cmd), do: {:ok, :done}
             end
           end
           """)

    # The three waits this service replies from.
    for wait <- [
          "{:ok, _v, _e} <- MaybeX.dispatch(cmd), :ok <- GetCrew.await_agent(n, m)",
          "{:ok, _v, _e} <- MaybeX.dispatch(cmd), do: Wire.once_read(id, v, reply)",
          "{:ok, _v, _e} <- MaybeX.dispatch(cmd), do: Wire.card_after(id, v)"
        ] do
      assert waits_after_dispatch?("""
             defmodule X do
               def handle_request(payload, state) do
                 with #{wait}, do: {:ok, :done}
               end
             end
             """)
    end

    # Nothing for the card face to wait on? Then it is not a gate at all.
    refute dispatches?("""
           defmodule CardProcedure do
             def call(payload, _command, _desk, args), do: {:ok, args}
           end
           """)

    # A card face that read the card BEFORE dispatching has not waited for its
    # own write.
    refute waits_after_dispatch?("""
           defmodule CardProcedure do
             def call(payload, command, desk, args) do
               with {:ok, card} <- Wire.card_after(args.card_id, 0),
                    {:ok, _v, _e} <- desk.dispatch(cmd),
                    do: {:ok, card}
             end
           end
           """)

    # And the real shape: dispatch, then read the card.
    assert waits_after_dispatch?("""
           defmodule CardProcedure do
             def call(payload, command, desk, args) do
               with {:ok, _v, _e} <- desk.dispatch(cmd),
                    do: Wire.card_after(args.card_id, 1)
             end
           end
           """)
  end

  defp responder_files do
    @dir
    |> Path.join("*/*_responder.ex")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp desk(file), do: file |> Path.dirname() |> Path.basename()

  # The calls a source makes, in source order, as {last alias segment, fun}.
  defp calls(source) do
    {_ast, reversed} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn node, acc -> {node, calls_in(node) ++ acc} end)

    Enum.reverse(reversed)
  end

  defp calls_in({{:., _, [module, fun]}, _, _args}) when is_atom(fun),
    do: [{module_name(module), fun}]

  defp calls_in(_node), do: []

  defp module_name({:__aliases__, _, mods}), do: List.last(mods)
  defp module_name(other), do: other

  defp dispatches?(source),
    do: Enum.any?(calls(source), fn {_module, fun} -> fun == :dispatch end)

  # A responder that dispatches nothing has no write to wait for: the read
  # desks, and the card desks, whose wait lives in CardProcedure.call (checked
  # by the test above).
  defp waits_after_dispatch?(source) do
    cs = calls(source)

    case Enum.drop_while(cs, fn {_module, fun} -> fun != :dispatch end) do
      [] -> true
      after_dispatch -> Enum.any?(after_dispatch, &wait?/1)
    end
  end

  defp wait?({:Wire, fun}), do: fun in [:card_after, :once_read]

  # Only a wait on this service's read model counts: Task.await_many is an
  # await_* call, and it reads nothing of the board.
  defp wait?({module, fun}) when is_atom(module) and is_atom(fun),
    do: reads?(module) and String.starts_with?(Atom.to_string(fun), "await_")

  defp wait?(_call), do: false

  # The query desks (GetBoards, GetCrew, GetLadder, GetGoal, GetCardById, ...)
  # and ReadModel itself, which is the shape every one of them uses.
  defp reads?(module),
    do: module == :ReadModel or String.starts_with?(Atom.to_string(module), "Get")
end
