defmodule MclKanban.BoardOverMeshTest do
  # End to end on a real store: the owner founds the crew and a board, then
  # agents work the board through the procedures exactly as a plain mesh_call
  # delivers them (text keys and values as {:text, _}, the signer's node id as
  # the atom key caller). Node ids are synthetic.
  use ExUnit.Case, async: false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AppointPrioritiser.{AppointPrioritiserV1, MaybeAppointPrioritiser}
  alias GuideCardLifecycle.AppointSupervisor.{AppointSupervisorV1, MaybeAppointSupervisor}
  alias GuideCardLifecycle.EnlistAgent.{EnlistAgentV1, MaybeEnlistAgent}

  alias MclKanban.AdoptGoal.AdoptGoalResponder
  alias MclKanban.ClaimCard.ClaimCardResponder
  alias MclKanban.ClaimNextCard.ClaimNextCardResponder
  alias MclKanban.CommentOnCard.CommentOnCardResponder
  alias MclKanban.DeferBoard.DeferBoardResponder
  alias MclKanban.DeferCard.DeferCardResponder
  alias MclKanban.DeferPackage.DeferPackageResponder
  alias MclKanban.EnlistAgent.EnlistAgentResponder
  alias MclKanban.FileCard.FileCardResponder
  alias MclKanban.FinishCard.FinishCardResponder
  alias MclKanban.GetCardById.GetCardByIdResponder
  alias MclKanban.GetGoal.GetGoalResponder
  alias MclKanban.GetLadder.GetLadderResponder
  alias MclKanban.GetMyCards.GetMyCardsResponder
  alias MclKanban.OpenBoard.OpenBoardResponder
  alias MclKanban.OpenPackage.OpenPackageResponder
  alias MclKanban.PrioritisePackage.PrioritisePackageResponder
  alias MclKanban.QueueCard.QueueCardResponder
  alias MclKanban.ReserveCard.ReserveCardResponder
  alias MclKanban.ResumeBoard.ResumeBoardResponder
  alias MclKanban.ResumeCard.ResumeCardResponder
  alias MclKanban.ResumePackage.ResumePackageResponder
  alias MclKanban.UnfileCard.UnfileCardResponder

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

      %{agent: %{name: ^agent}} =
        call(EnlistAgentResponder, sup, %{name: agent, node_id: hex(agent)})
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
      call(QueueCardResponder, agent, %{
        issue_ref: "#{repo}##{n}",
        title: "Card #{n}",
        kind: "slice"
      })

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
      |> Enum.map(fn agent ->
        Task.async(fn -> call(ClaimCardResponder, agent, %{card_id: id}) end)
      end)
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
    [last | taken] =
      Enum.reduce_while(1..500, [], fn _, acc ->
        case call(ClaimNextCardResponder, dan, %{}) do
          %{card: card} -> {:cont, [card | acc]}
          other -> {:halt, [other | acc]}
        end
      end)

    assert last == %{reason: "board_empty"}
    assert first in Enum.map(taken, & &1.card_id)
  end

  test "a caller the crew does not know gets nothing", %{repo: repo} do
    assert %{reason: "not_enlisted"} = call(GetMyCardsResponder, "stranger" <> uniq(), %{})

    assert %{reason: "not_enlisted"} =
             call(QueueCardResponder, "stranger" <> uniq(), %{
               issue_ref: "#{repo}#99",
               title: "x",
               kind: "bug"
             })
  end

  test "a plain agent may not enlist, and naming a role in the payload changes nothing", %{
    sup: sup
  } do
    bob = enlist(sup)

    assert %{reason: "not_permitted"} =
             call(EnlistAgentResponder, bob, %{
               name: "eve" <> uniq(),
               node_id: hex("eve"),
               role: "owner"
             })
  end

  test "a refusal names its reason", %{sup: sup, repo: repo} do
    bob = enlist(sup)
    queue(bob, repo, 41)

    assert %{reason: "already_on_board"} =
             call(QueueCardResponder, bob, %{
               issue_ref: "#{repo}#41",
               title: "again",
               kind: "slice"
             })

    assert %{reason: "invalid_kind"} =
             call(QueueCardResponder, bob, %{issue_ref: "#{repo}#77", title: "x", kind: "epic"})

    assert %{reason: "unknown_board"} =
             call(QueueCardResponder, bob, %{
               issue_ref: "example-org/none#1",
               title: "x",
               kind: "bug"
             })
  end

  test "the supervisor opens a package and files a card, the prioritiser ranks it, agents read the ladder",
       %{sup: sup, repo: repo} do
    pia = enlist(sup)
    {:ok, appoint} = AppointPrioritiserV1.new(%{name: pia, by: Actor.owner()})
    {:ok, _, _} = MaybeAppointPrioritiser.dispatch(appoint)

    ref = "#{repo}#900" <> uniq()
    bob = enlist(sup)
    id = queue(bob, repo, 901)

    assert %{reason: "not_permitted"} =
             call(OpenPackageResponder, bob, %{issue_ref: ref, title: "Ship it"})

    assert %{package: %{issue_ref: ^ref}} =
             call(OpenPackageResponder, sup, %{issue_ref: ref, title: "Ship it"})

    assert %{reason: "already_open"} =
             call(OpenPackageResponder, sup, %{issue_ref: ref, title: "Ship it"})

    assert %{card: %{work_package: ^ref}} =
             call(FileCardResponder, sup, %{card_id: id, package_ref: ref})

    assert %{package: %{issue_ref: ^ref, rank: 1}} =
             call(PrioritisePackageResponder, pia, %{issue_ref: ref, rank: 1, rationale: "first"})

    assert %{reason: "unknown_package"} =
             call(FileCardResponder, sup, %{card_id: id, package_ref: "#{repo}#999999"})

    %{packages: packages} = call(GetLadderResponder, bob, %{})
    package = Enum.find(packages, &(&1.issue_ref == ref))
    assert package.rank == 1
    assert [%{card_id: ^id}] = package.cards

    assert %{card: card} = call(UnfileCardResponder, sup, %{card_id: id})
    refute Map.has_key?(card, :work_package)
  end

  test "the prioritiser pauses a repo, a package or a card over the mesh, and nobody is handed it until resumed (#17)",
       %{sup: sup} do
    pia = enlist(sup)
    {:ok, appoint} = AppointPrioritiserV1.new(%{name: pia, by: Actor.owner()})
    {:ok, _, _} = MaybeAppointPrioritiser.dispatch(appoint)

    repo = "example-org/paused" <> uniq()
    %{board: %{repo: ^repo}} = call(OpenBoardResponder, sup, %{repo: repo})
    bob = enlist(sup)
    id = queue(bob, repo, 1)
    %{card: %{lane: ^bob}} = call(ReserveCardResponder, sup, %{card_id: id, lane: bob})

    claims_mine? = fn ->
      match?(%{card: %{card_id: ^id}}, call(ClaimNextCardResponder, bob, %{}))
    end

    assert %{reason: "not_permitted"} = call(DeferBoardResponder, bob, %{repo: repo, reason: "x"})

    assert %{board: %{repo: ^repo, deferred: 1}} =
             call(DeferBoardResponder, pia, %{repo: repo, reason: "not now"})

    refute claims_mine?.()
    assert %{board: %{repo: ^repo, deferred: 0}} = call(ResumeBoardResponder, pia, %{repo: repo})

    assert %{card: %{state: "deferred", deferred: 1}} =
             call(DeferCardResponder, pia, %{card_id: id, reason: "not now"})

    refute claims_mine?.()

    assert %{card: %{state: "queued", deferred: 0}} =
             call(ResumeCardResponder, pia, %{card_id: id})

    ref = "#{repo}#900"

    %{package: %{issue_ref: ^ref}} =
      call(OpenPackageResponder, sup, %{issue_ref: ref, title: "P"})

    %{card: _} = call(FileCardResponder, sup, %{card_id: id, package_ref: ref})

    assert %{package: %{issue_ref: ^ref, deferred: 1}} =
             call(DeferPackageResponder, pia, %{issue_ref: ref, reason: "later"})

    refute claims_mine?.()

    assert %{package: %{issue_ref: ^ref, deferred: 0}} =
             call(ResumePackageResponder, pia, %{issue_ref: ref})

    assert claims_mine?.()
  end

  test "the supervisor adopts the crew's goal; every claim carries its sentence and serves its packages first (#18)",
       %{sup: sup} do
    repo = "example-org/goal" <> uniq()
    %{board: %{repo: ^repo}} = call(OpenBoardResponder, sup, %{repo: repo})
    bob = enlist(sup)
    ref = "#{repo}#100"
    %{package: _} = call(OpenPackageResponder, sup, %{issue_ref: ref, title: "The goal"})
    id = queue(bob, repo, 1)
    %{card: _} = call(FileCardResponder, sup, %{card_id: id, package_ref: ref})

    assert %{reason: "not_permitted"} =
             call(AdoptGoalResponder, bob, %{goal: "Mine", packages: [ref]})

    assert %{goal: %{goal: "So the goal ships", packages: [^ref]}} =
             call(AdoptGoalResponder, sup, %{goal: "So the goal ships", packages: [ref]})

    assert %{goal: %{goal: "So the goal ships", packages: [^ref], by: ^sup, at: at}} =
             call(GetGoalResponder, bob, %{})

    assert is_integer(at)

    assert %{card: %{card_id: ^id}, goal: "So the goal ships"} =
             call(ClaimNextCardResponder, bob, %{})
  end
end
