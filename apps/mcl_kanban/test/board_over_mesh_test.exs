defmodule MclKanban.BoardOverMeshTest do
  # End to end on a real store: the owner founds the crew and a board, then
  # agents work the board through the procedures exactly as a plain mesh_call
  # delivers them (text keys and values as {:text, _}, the signer's node id as
  # the atom key caller). Node ids are synthetic.
  use ExUnit.Case, async: false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AppointSupervisor.{AppointSupervisorV1, MaybeAppointSupervisor}
  alias GuideCardLifecycle.EnlistAgent.{EnlistAgentV1, MaybeEnlistAgent}

  alias MclKanban.ClaimCard.ClaimCardResponder
  alias MclKanban.ClaimNextCard.ClaimNextCardResponder
  alias MclKanban.CommentOnCard.CommentOnCardResponder
  alias MclKanban.EnlistAgent.EnlistAgentResponder
  alias MclKanban.FinishCard.FinishCardResponder
  alias MclKanban.GetCardById.GetCardByIdResponder
  alias MclKanban.GetMyCards.GetMyCardsResponder
  alias MclKanban.OpenBoard.OpenBoardResponder
  alias MclKanban.QueueCard.QueueCardResponder

  @moduletag timeout: 120_000

  defp node_id(name), do: :crypto.hash(:sha256, "synthetic kanban node " <> name)
  defp hex(name), do: Base.encode16(node_id(name), case: :lower)

  defp wire(caller, args) do
    args
    |> Map.new(fn {k, v} -> {{:text, to_string(k)}, text(v)} end)
    |> Map.put(:caller, node_id(caller))
  end

  defp text(v) when is_binary(v), do: {:text, v}
  defp text(v) when is_list(v), do: Enum.map(v, &text/1)
  defp text(v) when is_map(v), do: Map.new(v, fn {k, x} -> {{:text, to_string(k)}, text(x)} end)
  defp text(v), do: v

  defp call(responder, caller, args) do
    {:ok, state} = responder.init([])
    {:reply, reply, _} = responder.handle_request(wire(caller, args), state)
    plain(reply)
  end

  defp plain({:text, t}), do: t
  defp plain(m) when is_map(m), do: Map.new(m, fn {k, v} -> {k, plain(v)} end)
  defp plain(l) when is_list(l), do: Enum.map(l, &plain/1)
  defp plain(v), do: v

  defp uniq, do: Integer.to_string(System.unique_integer([:positive]))

  setup_all do
    sup = "sup" <> uniq()
    {:ok, enlist} = EnlistAgentV1.new(%{name: sup, node_id: hex(sup), by: Actor.owner()})
    {:ok, _, _} = MaybeEnlistAgent.dispatch(enlist)
    {:ok, appoint} = AppointSupervisorV1.new(%{name: sup, by: Actor.owner()})
    {:ok, _, _} = MaybeAppointSupervisor.dispatch(appoint)

    for name <- ~w(bob cyd) do
      agent = name <> uniq()
      %{agent: %{name: ^agent}} = call(EnlistAgentResponder, sup, %{name: agent, node_id: hex(agent)})
    end

    repo = "example-org/kanban" <> uniq()
    %{board: %{repo: ^repo}} = call(OpenBoardResponder, sup, %{repo: repo})
    {:ok, sup: sup, repo: repo}
  end

  defp enlist(sup) do
    name = "agent" <> uniq()
    %{agent: %{name: ^name}} = call(EnlistAgentResponder, sup, %{name: name, node_id: hex(name)})
    name
  end

  defp queue(agent, repo, n) do
    %{card_id: id} =
      call(QueueCardResponder, agent, %{issue_ref: "#{repo}##{n}", title: "Card #{n}", kind: "slice"})

    id
  end

  test "an agent queues and claims a card through the procedures", %{sup: sup, repo: repo} do
    bob = enlist(sup)
    id = queue(bob, repo, 1)

    assert %{card: card} = call(ClaimCardResponder, bob, %{card_id: id})
    assert card.card_id == id
    assert card.holder == bob
    assert card.state == "claimed"
    assert card.status == 2
    assert card.board == repo
    assert card.colour == "#63ba3c"

    assert %{cards: [%{card_id: ^id}]} = call(GetMyCardsResponder, bob, %{})

    assert %{comment_id: _} = call(CommentOnCardResponder, bob, %{card_id: id, text: "picked up"})
    assert %{card: %{comment_count: 1, comments: [%{text: "picked up"}]}} =
             call(GetCardByIdResponder, bob, %{card_id: id})

    assert %{card: %{state: "finished"}} =
             call(FinishCardResponder, bob, %{card_id: id, result: "done"})
  end

  test "two simultaneous claims give one card and one already_claimed", %{sup: sup, repo: repo} do
    bob = enlist(sup)
    cyd = enlist(sup)
    id = queue(bob, repo, 2)

    replies =
      [bob, cyd]
      |> Enum.map(fn agent -> Task.async(fn -> call(ClaimCardResponder, agent, %{card_id: id}) end) end)
      |> Enum.map(&Task.await(&1, 30_000))

    assert Enum.count(replies, &match?(%{card: %{state: "claimed"}}, &1)) == 1
    assert Enum.count(replies, &(&1 == %{reason: "already_claimed"})) == 1
  end

  test "claim_next_card takes the agent's next card, then reports an empty board", %{sup: sup} do
    repo = "example-org/next" <> uniq()
    %{board: _} = call(OpenBoardResponder, sup, %{repo: repo})
    dan = enlist(sup)
    first = queue(dan, repo, 1)

    # Other tests leave queued cards behind; drain until this test's card is
    # taken, then until the board has nothing left for dan.
    taken = Stream.repeatedly(fn -> call(ClaimNextCardResponder, dan, %{}) end) |> Enum.take_while(&match?(%{card: _}, &1))
    assert Enum.any?(taken, &(&1.card.card_id == first))
    assert %{reason: "board_empty"} = call(ClaimNextCardResponder, dan, %{})
  end

  test "a caller the crew does not know gets nothing", %{repo: repo} do
    assert %{reason: "not_enlisted"} = call(GetMyCardsResponder, "stranger" <> uniq(), %{})

    assert %{reason: "not_enlisted"} =
             call(QueueCardResponder, "stranger" <> uniq(), %{issue_ref: "#{repo}#99", title: "x", kind: "bug"})
  end

  test "a plain agent may not enlist, and naming a role in the payload changes nothing", %{sup: sup} do
    bob = enlist(sup)

    assert %{reason: "not_permitted"} =
             call(EnlistAgentResponder, bob, %{name: "eve" <> uniq(), node_id: hex("eve"), role: "owner"})
  end

  test "a refusal names its reason", %{sup: sup, repo: repo} do
    bob = enlist(sup)
    assert %{reason: "already_on_board"} = call(QueueCardResponder, bob, %{issue_ref: "#{repo}#1", title: "again", kind: "slice"}) |> refused_or_first(bob, repo)
    assert %{reason: "invalid_kind"} = call(QueueCardResponder, bob, %{issue_ref: "#{repo}#77", title: "x", kind: "epic"})
    assert %{reason: "unknown_board"} = call(QueueCardResponder, bob, %{issue_ref: "example-org/none#1", title: "x", kind: "bug"})
  end

  # Card 1 of the shared repo may not exist yet when this test runs first.
  defp refused_or_first(%{card_id: _}, bob, repo),
    do: call(QueueCardResponder, bob, %{issue_ref: "#{repo}#1", title: "again", kind: "slice"})

  defp refused_or_first(reply, _bob, _repo), do: reply
end
