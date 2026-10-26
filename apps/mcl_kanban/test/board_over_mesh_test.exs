defmodule MclKanban.BoardOverMeshTest do
  # End to end on a real store: the owner founds the crew and a board, then
  # agents work the board through the procedures exactly as a plain mesh_call
  # delivers them (text keys and values as {:text, _}, the signer's node id as
  # the atom key caller). Node ids are synthetic.
  use ExUnit.Case, async: false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AppointOperator.{AppointOperatorV1, MaybeAppointOperator}
  alias GuideCardLifecycle.AppointPrioritiser.{AppointPrioritiserV1, MaybeAppointPrioritiser}
  alias GuideCardLifecycle.AppointSupervisor.{AppointSupervisorV1, MaybeAppointSupervisor}
  alias GuideCardLifecycle.EnlistAgent.{EnlistAgentV1, MaybeEnlistAgent}

  alias MclKanban.AdoptGoal.AdoptGoalResponder
  alias MclKanban.AppointOperator.AppointOperatorResponder
  alias MclKanban.AppointSupervisor.AppointSupervisorResponder
  alias MclKanban.ArchiveBoard.ArchiveBoardResponder
  alias MclKanban.ClaimCard.ClaimCardResponder
  alias MclKanban.ClaimNextCard.ClaimNextCardResponder
  alias MclKanban.CommentOnCard.CommentOnCardResponder
  alias MclKanban.DeferBoard.DeferBoardResponder
  alias MclKanban.DeferCard.DeferCardResponder
  alias MclKanban.DeferPackage.DeferPackageResponder
  alias MclKanban.DischargeAgent.DischargeAgentResponder
  alias MclKanban.EnlistAgent.EnlistAgentResponder
  alias MclKanban.FileCard.FileCardResponder
  alias MclKanban.FinishCard.FinishCardResponder
  alias MclKanban.GetBoards.GetBoardsResponder
  alias MclKanban.GetCardById.GetCardByIdResponder
  alias MclKanban.GetCrew.GetCrewResponder
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

  # How long a read waits for the projection to show the write it depends on
  # (#28). The production query side waits the same way; see QueryBoards.ReadModel.
  @read_model_await_ms 5_000

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

    {:ok, enlist} =
      EnlistAgentV1.new(%{name: sup, node_id: hex(sup), crew: "home", by: Actor.owner()})

    {:ok, _, _} = MaybeEnlistAgent.dispatch(enlist)
    {:ok, appoint} = AppointSupervisorV1.new(%{name: sup, by: Actor.owner()})
    {:ok, _, _} = MaybeAppointSupervisor.dispatch(appoint)

    # #28: enlisting and discharging belong to the crew's operator (or the
    # owner), so the crew that founds this board has one.
    {:ok, operator} = AppointOperatorV1.new(%{crew: "home", name: sup, by: Actor.owner()})
    {:ok, _, _} = MaybeAppointOperator.dispatch(operator)

    for name <- ~w(bob cyd) do
      agent = name <> uniq()

      %{agent: %{name: ^agent, crew: "home"}} =
        call(EnlistAgentResponder, sup, %{name: agent, node_id: hex(agent), crew: "home"})
    end

    repo = "example-org/kanban" <> uniq()
    %{board: %{repo: ^repo}} = call(OpenBoardResponder, sup, %{repo: repo})
    {:ok, sup: sup, repo: repo}
  end

  defp enlist(sup, crew \\ "home") do
    name = "agent" <> uniq()

    %{agent: %{name: ^name, crew: ^crew}} =
      call(EnlistAgentResponder, sup, %{name: name, node_id: hex(name), crew: crew})

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

  # The reads the four #37 desks must agree with: one call each, no waiting.
  defp boards(sup), do: call(GetBoardsResponder, sup, %{}).boards

  defp crew_names(sup) do
    for %{agents: agents} <- call(GetCrewResponder, sup, %{}).crews,
        agent <- agents,
        do: agent.name
  end

  # The read model takes the crew row and the agent row in separate
  # transactions, so it can hold a crew before it holds the agent just enlisted
  # into it: a read taken straight after an enlist can still miss that agent.
  # Poll the read, bounded, rather than sleeping a guess (#28).
  defp crews_once_seeded(caller, seeded?),
    do:
      crews_once_seeded(
        caller,
        seeded?,
        System.monotonic_time(:millisecond) + @read_model_await_ms
      )

  defp crews_once_seeded(caller, seeded?, deadline) do
    case seeded_crews(caller, seeded?) do
      nil ->
        retry_crews(caller, seeded?, deadline, System.monotonic_time(:millisecond) >= deadline)

      crews ->
        crews
    end
  end

  # nil while the caller is not enlisted yet or the write has not landed.
  defp seeded_crews(caller, seeded?) do
    with %{crews: crews} <- call(GetCrewResponder, caller, %{}),
         true <- seeded?.(crews) do
      crews
    else
      _ -> nil
    end
  end

  defp retry_crews(_caller, _seeded?, _deadline, true),
    do: flunk("the read model did not show the write within #{@read_model_await_ms} ms")

  defp retry_crews(caller, seeded?, deadline, false) do
    Process.sleep(15)
    crews_once_seeded(caller, seeded?, deadline)
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
               crew: "home",
               role: "owner"
             })
  end

  test "a second crew is founded by the owner, runs its own operator, and get_crew shows both (#28)",
       %{sup: sup} do
    night = "night" <> uniq()
    eve = "eve" <> uniq()

    # A crew no agent is in yet has no operator to enlist into it: the owner
    # founds it, then appoints the operator who runs it.
    {:ok, found} =
      EnlistAgentV1.new(%{name: eve, node_id: hex(eve), crew: night, by: Actor.owner()})

    {:ok, _, _} = MaybeEnlistAgent.dispatch(found)
    {:ok, operator} = AppointOperatorV1.new(%{crew: night, name: eve, by: Actor.owner()})
    {:ok, _, _} = MaybeAppointOperator.dispatch(operator)

    # The new operator enlists into its own crew, over the mesh, and only there.
    dan = enlist(eve, night)

    assert %{reason: "not_permitted"} =
             call(EnlistAgentResponder, eve, %{
               name: "outsider" <> uniq(),
               node_id: hex("outsider" <> uniq()),
               crew: "home"
             })

    crews =
      crews_once_seeded(dan, fn crews ->
        Enum.any?(crews, fn
          %{crew: ^night, operator: %{name: ^eve}, agents: agents} ->
            Enum.any?(agents, &(&1.name == dan)) and Enum.any?(agents, &(&1.name == eve))

          _other ->
            false
        end)
      end)

    assert %{crew: ^night, operator: %{name: ^eve}, agents: agents} =
             Enum.find(crews, &(&1.crew == night))

    assert %{roles: dan_roles} = Enum.find(agents, &(&1.name == dan))
    assert dan_roles == ["agent"]

    assert %{roles: eve_roles} = Enum.find(agents, &(&1.name == eve))
    assert "operator" in eve_roles
    assert %{crew: "home", operator: %{name: ^sup}} = Enum.find(crews, &(&1.crew == "home"))

    # The owner's rule, over the mesh: appointing is the owner's alone.
    assert %{reason: "not_permitted"} =
             call(AppointOperatorResponder, sup, %{crew: "home", name: sup})

    # Only a crew's own operator discharges from it.
    assert %{reason: "not_permitted"} = call(DischargeAgentResponder, eve, %{name: sup})
    assert %{agent: %{name: ^dan}} = call(DischargeAgentResponder, eve, %{name: dan})
  end

  # #37: a command's reply waits for the read model, so each read below
  # follows its own command with no polling and still sees the write. One desk
  # per test, so a failure names the desk that stopped waiting.
  test "open_board's reply is followed by a get_boards that lists the board", %{sup: sup} do
    repo = "example-org/opened" <> uniq()

    %{board: %{repo: ^repo}} = call(OpenBoardResponder, sup, %{repo: repo})
    assert Enum.any?(boards(sup), &(&1.repo == repo and &1.archived == 0))
  end

  test "archive_board's reply is followed by a get_boards that shows it archived", %{sup: sup} do
    repo = "example-org/archived" <> uniq()

    %{board: %{repo: ^repo}} = call(OpenBoardResponder, sup, %{repo: repo})
    %{board: %{repo: ^repo}} = call(ArchiveBoardResponder, sup, %{repo: repo})
    assert Enum.any?(boards(sup), &(&1.repo == repo and &1.archived == 1))
  end

  test "open_package's reply is followed by a get_ladder that lists the package", %{
    sup: sup,
    repo: repo
  } do
    ref = "#{repo}#37" <> uniq()

    %{package: %{issue_ref: ^ref}} =
      call(OpenPackageResponder, sup, %{issue_ref: ref, title: "Ship it"})

    %{packages: packages} = call(GetLadderResponder, sup, %{})
    assert Enum.any?(packages, &(&1.issue_ref == ref))
  end

  test "discharge_agent's reply is followed by a get_crew that no longer lists the agent", %{
    sup: sup
  } do
    leaving = enlist(sup)
    assert leaving in crew_names(sup)

    %{agent: %{name: ^leaving}} = call(DischargeAgentResponder, sup, %{name: leaving})
    refute leaving in crew_names(sup)
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
