defmodule GuideCardLifecycle.CrossCrewTest do
  # The cross-crew rules (#29), with two crews enlisted (TestCrew.crews/0):
  # home, run by bob, where ada is the supervisor and pia the prioritiser,
  # and night, run by eve. A board has a home crew, and its cards and
  # packages follow it. Only the home crew orders a board's work; any crew
  # may post work on it; a lane may be reserved for a crew.
  use ExUnit.Case, async: true

  import GuideCardLifecycle.TestCrew

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.BoardState
  alias GuideCardLifecycle.CardAggregate
  alias GuideCardLifecycle.CardState
  alias GuideCardLifecycle.CardStatus
  alias GuideCardLifecycle.CrewState
  alias GuideCardLifecycle.IssueRef
  alias GuideCardLifecycle.PackageState

  alias GuideCardLifecycle.ArchiveBoard.{ArchiveBoardV1, MaybeArchiveBoard}
  alias GuideCardLifecycle.BlockCard.{BlockCardV1, MaybeBlockCard}
  alias GuideCardLifecycle.ClaimCard.{ClaimCardV1, MaybeClaimCard}
  alias GuideCardLifecycle.CommentOnCard.{CommentOnCardV1, MaybeCommentOnCard}
  alias GuideCardLifecycle.DeferBoard.{DeferBoardV1, MaybeDeferBoard}
  alias GuideCardLifecycle.DeferCard.{DeferCardV1, MaybeDeferCard}
  alias GuideCardLifecycle.DeferPackage.{DeferPackageV1, MaybeDeferPackage}
  alias GuideCardLifecycle.DischargeAgent.{DischargeAgentV1, MaybeDischargeAgent}
  alias GuideCardLifecycle.FileCard.{FileCardV1, MaybeFileCard}
  alias GuideCardLifecycle.FinishCard.{FinishCardV1, MaybeFinishCard}
  alias GuideCardLifecycle.HandOverBoard.{HandOverBoardV1, MaybeHandOverBoard}
  alias GuideCardLifecycle.LiftCardReservation.{LiftCardReservationV1, MaybeLiftCardReservation}
  alias GuideCardLifecycle.LinkCard.{LinkCardV1, MaybeLinkCard}
  alias GuideCardLifecycle.OpenBoard.{MaybeOpenBoard, OpenBoardV1}
  alias GuideCardLifecycle.OpenPackage.{MaybeOpenPackage, OpenPackageV1}
  alias GuideCardLifecycle.PrioritiseCard.{MaybePrioritiseCard, PrioritiseCardV1}
  alias GuideCardLifecycle.PrioritisePackage.{MaybePrioritisePackage, PrioritisePackageV1}
  alias GuideCardLifecycle.QueueCard.{MaybeQueueCard, QueueCardV1}
  alias GuideCardLifecycle.ReclassifyCard.{MaybeReclassifyCard, ReclassifyCardV1}
  alias GuideCardLifecycle.ReleaseCard.{MaybeReleaseCard, ReleaseCardV1}
  alias GuideCardLifecycle.ReserveCard.{MaybeReserveCard, ReserveCardV1}
  alias GuideCardLifecycle.ResumeBoard.{MaybeResumeBoard, ResumeBoardV1}
  alias GuideCardLifecycle.ResumeCard.{MaybeResumeCard, ResumeCardV1}
  alias GuideCardLifecycle.ResumePackage.{MaybeResumePackage, ResumePackageV1}
  alias GuideCardLifecycle.RewordCard.{MaybeRewordCard, RewordCardV1}
  alias GuideCardLifecycle.TagCard.{MaybeTagCard, TagCardV1}
  alias GuideCardLifecycle.UnblockCard.{MaybeUnblockCard, UnblockCardV1}
  alias GuideCardLifecycle.UnfileCard.{MaybeUnfileCard, UnfileCardV1}
  alias GuideCardLifecycle.WithdrawCard.{MaybeWithdrawCard, WithdrawCardV1}

  @ref "example-org/widget#7"
  @package "example-org/widget#1"
  @repo "example-org/widget"

  # The names home_crew_desks/0 lists, one test each.
  @desk_names [
    "rank",
    "defer",
    "resume",
    "withdraw",
    "reword",
    "reclassify",
    "reserve",
    "lift",
    "file",
    "unfile",
    "archive board",
    "defer board",
    "resume board",
    "rank package",
    "defer package",
    "resume package"
  ]

  defp card_id, do: IssueRef.card_id(@ref)
  defp package_id, do: IssueRef.package_id(@package)

  defp cmd(module, fields) do
    {:ok, cmd} = module.new(fields)
    cmd
  end

  defp fold(state, events, module), do: Enum.reduce(events, state, &module.apply_event(&2, &1))

  defp run(state, desk, cmd, module \\ CardState) do
    {:ok, events} = desk.handle(state, cmd)
    fold(state, events, module)
  end

  # A card on a board whose home crew is `crew`: the board's dispatch puts it
  # on the command, the way MaybeQueueCard.dispatch/1 does from the board.
  defp card_of(crew) do
    queue =
      cmd(QueueCardV1, %{issue_ref: @ref, title: "Draw it", kind: "slice", by: actor("cyd")})

    run(CardState.new(card_id()), MaybeQueueCard, %{queue | home_crew: crew})
  end

  defp claimed(card, name) do
    run(card, MaybeClaimCard, cmd(ClaimCardV1, %{card_id: card_id(), by: operator_actor(name)}))
  end

  defp board_of(crew) do
    BoardState.apply_event(BoardState.new(IssueRef.board_id(@repo)), %{
      event_type: "board_opened_v1",
      board_id: IssueRef.board_id(@repo),
      repo: @repo,
      home_crew: crew
    })
  end

  defp package_of(crew) do
    open = cmd(OpenPackageV1, %{issue_ref: @package, title: "Ship it", by: Actor.owner()})
    run(PackageState.new(package_id()), MaybeOpenPackage, %{open | home_crew: crew}, PackageState)
  end

  # Every desk that orders a board's work: its state on a board of the given
  # crew, and the command a given actor would send there.
  defp home_crew_desks do
    [
      {"rank", MaybePrioritiseCard, &card_of/1,
       &cmd(PrioritiseCardV1, %{card_id: card_id(), rank: 3, rationale: "first", by: &1})},
      {"defer", MaybeDeferCard, &card_of/1,
       &cmd(DeferCardV1, %{card_id: card_id(), reason: "later", by: &1})},
      {"resume", MaybeResumeCard, &deferred_card_of/1,
       &cmd(ResumeCardV1, %{card_id: card_id(), by: &1})},
      {"withdraw", MaybeWithdrawCard, &card_of/1,
       &cmd(WithdrawCardV1, %{card_id: card_id(), reason: "not ours", by: &1})},
      {"reword", MaybeRewordCard, &card_of/1,
       &cmd(RewordCardV1, %{card_id: card_id(), title: "Draw it better", by: &1})},
      {"reclassify", MaybeReclassifyCard, &card_of/1,
       &cmd(ReclassifyCardV1, %{card_id: card_id(), kind: "bug", by: &1})},
      {"reserve", MaybeReserveCard, &card_of/1,
       &cmd(ReserveCardV1, %{card_id: card_id(), lane: "cyd", lane_node_id: hex("cyd"), by: &1})},
      {"lift", MaybeLiftCardReservation, &reserved_card_of/1,
       &cmd(LiftCardReservationV1, %{card_id: card_id(), by: &1})},
      {"file", MaybeFileCard, &card_of/1,
       &cmd(FileCardV1, %{card_id: card_id(), package_ref: @package, by: &1})},
      {"unfile", MaybeUnfileCard, &filed_card_of/1,
       &cmd(UnfileCardV1, %{card_id: card_id(), by: &1})},
      {"archive board", MaybeArchiveBoard, &board_of/1,
       &cmd(ArchiveBoardV1, %{repo: @repo, by: &1})},
      {"defer board", MaybeDeferBoard, &board_of/1,
       &cmd(DeferBoardV1, %{repo: @repo, reason: "later", by: &1})},
      {"resume board", MaybeResumeBoard, &deferred_board_of/1,
       &cmd(ResumeBoardV1, %{repo: @repo, by: &1})},
      {"rank package", MaybePrioritisePackage, &package_of/1,
       &cmd(PrioritisePackageV1, %{package_id: package_id(), rank: 1, rationale: "first", by: &1})},
      {"defer package", MaybeDeferPackage, &package_of/1,
       &cmd(DeferPackageV1, %{package_id: package_id(), reason: "later", by: &1})},
      {"resume package", MaybeResumePackage, &deferred_package_of/1,
       &cmd(ResumePackageV1, %{package_id: package_id(), by: &1})}
    ]
  end

  defp deferred_card_of(crew) do
    run(
      card_of(crew),
      MaybeDeferCard,
      cmd(DeferCardV1, %{card_id: card_id(), reason: "later", by: Actor.owner()})
    )
  end

  defp reserved_card_of(crew) do
    run(
      card_of(crew),
      MaybeReserveCard,
      cmd(ReserveCardV1, %{
        card_id: card_id(),
        lane: "cyd",
        lane_node_id: hex("cyd"),
        by: Actor.owner()
      })
    )
  end

  defp filed_card_of(crew) do
    run(
      card_of(crew),
      MaybeFileCard,
      cmd(FileCardV1, %{card_id: card_id(), package_ref: @package, by: Actor.owner()})
    )
  end

  defp deferred_board_of(crew) do
    run(
      board_of(crew),
      MaybeDeferBoard,
      cmd(DeferBoardV1, %{repo: @repo, reason: "later", by: Actor.owner()}),
      BoardState
    )
  end

  defp deferred_package_of(crew) do
    run(
      package_of(crew),
      MaybeDeferPackage,
      cmd(DeferPackageV1, %{package_id: package_id(), reason: "later", by: Actor.owner()}),
      PackageState
    )
  end

  describe "a board's home crew" do
    test "open_board names it, and a board opened before #29 belongs to the first crew" do
      {:ok, cmd} = OpenBoardV1.new(%{repo: @repo, crew: "night", by: operator_actor("eve")})

      assert {:ok, [%{event_type: "board_opened_v1", home_crew: "night"}]} =
               MaybeOpenBoard.handle(BoardState.new(cmd.board_id), cmd)

      old =
        BoardState.apply_event(BoardState.new(cmd.board_id), %{
          event_type: "board_opened_v1",
          board_id: cmd.board_id,
          repo: @repo
        })

      assert old.home_crew == "home"
    end

    test "a board opened without naming a crew belongs to its opener's crew, or home for the owner" do
      {:ok, eve} = OpenBoardV1.new(%{repo: @repo, by: operator_actor("eve")})
      assert eve.crew == "night"

      {:ok, owner} = OpenBoardV1.new(%{repo: @repo, by: Actor.owner()})
      assert owner.crew == "home"
    end

    test "an operator opens boards for its own crew only; the supervisor too" do
      {:ok, eve} = OpenBoardV1.new(%{repo: @repo, crew: "home", by: operator_actor("eve")})
      assert {:error, :not_home_crew} = MaybeOpenBoard.handle(BoardState.new(eve.board_id), eve)

      {:ok, ada} = OpenBoardV1.new(%{repo: @repo, crew: "night", by: operator_actor("ada")})
      assert {:error, :not_home_crew} = MaybeOpenBoard.handle(BoardState.new(ada.board_id), ada)

      {:ok, owner} = OpenBoardV1.new(%{repo: @repo, crew: "night", by: Actor.owner()})

      assert {:ok, [%{home_crew: "night"}]} =
               MaybeOpenBoard.handle(BoardState.new(owner.board_id), owner)
    end

    test "a plain agent opens no board, in any crew" do
      {:ok, cyd} = OpenBoardV1.new(%{repo: @repo, by: operator_actor("cyd")})
      assert {:error, :not_permitted} = MaybeOpenBoard.handle(BoardState.new(cyd.board_id), cyd)
    end

    test "a crew name that is not one is refused" do
      assert {:error, :invalid_crew} =
               OpenBoardV1.new(%{repo: @repo, crew: "no spaces", by: Actor.owner()})
    end

    test "a card queued before #29 follows the first crew" do
      queue =
        cmd(QueueCardV1, %{issue_ref: @ref, title: "Draw it", kind: "slice", by: actor("cyd")})

      assert run(CardState.new(card_id()), MaybeQueueCard, queue).home_crew == "home"
      assert card_of("night").home_crew == "night"
    end
  end

  describe "ordering a board's work belongs to its home crew" do
    for name <- @desk_names do
      test "#{name}: the home crew's operator may, another crew's operator is refused not_home_crew" do
        {_name, desk, state, command} =
          Enum.find(home_crew_desks(), &(elem(&1, 0) == unquote(name)))

        assert {:ok, [_ | _]} = desk.handle(state.("night"), command.(operator_actor("eve")))
        assert {:ok, [_ | _]} = desk.handle(state.("home"), command.(operator_actor("bob")))

        assert {:error, :not_home_crew} =
                 desk.handle(state.("home"), command.(operator_actor("eve")))

        assert {:error, :not_home_crew} =
                 desk.handle(state.("night"), command.(operator_actor("bob")))
      end

      test "#{name}: the owner may on every crew's board" do
        {_name, desk, state, command} =
          Enum.find(home_crew_desks(), &(elem(&1, 0) == unquote(name)))

        for crew <- ["home", "night"],
            do: assert({:ok, [_ | _]} = desk.handle(state.(crew), command.(Actor.owner())))
      end

      test "#{name}: a plain agent of the home crew is still not permitted" do
        {_name, desk, state, command} =
          Enum.find(home_crew_desks(), &(elem(&1, 0) == unquote(name)))

        assert {:error, :not_permitted} =
                 desk.handle(state.("home"), command.(operator_actor("cyd")))
      end
    end

    test "the supervisor and the prioritiser of the home crew act on its boards only" do
      night = card_of("night")
      home = card_of("home")
      rank = &cmd(PrioritiseCardV1, %{card_id: card_id(), rank: 3, rationale: "first", by: &1})
      withdraw = &cmd(WithdrawCardV1, %{card_id: card_id(), reason: "no", by: &1})

      assert {:ok, [_]} = MaybePrioritiseCard.handle(home, rank.(operator_actor("pia")))

      assert {:error, :not_home_crew} =
               MaybePrioritiseCard.handle(night, rank.(operator_actor("pia")))

      assert {:ok, [_]} = MaybeWithdrawCard.handle(home, withdraw.(operator_actor("ada")))

      assert {:error, :not_home_crew} =
               MaybeWithdrawCard.handle(night, withdraw.(operator_actor("ada")))
    end

    test "a holder from another crew does not reword the card it holds" do
      reword = &cmd(RewordCardV1, %{card_id: card_id(), title: "Mine now", by: &1})

      assert {:error, :not_home_crew} =
               MaybeRewordCard.handle(
                 claimed(card_of("home"), "eve"),
                 reword.(operator_actor("eve"))
               )

      assert {:ok, [_]} =
               MaybeRewordCard.handle(
                 claimed(card_of("home"), "cyd"),
                 reword.(operator_actor("cyd"))
               )
    end

    test "a package opened on a board takes the board's home crew; open needs the home crew" do
      open = &cmd(OpenPackageV1, %{issue_ref: @package, title: "Ship it", by: &1})
      night = %{open.(operator_actor("eve")) | home_crew: "night"}

      assert {:ok, [%{home_crew: "night"}]} =
               MaybeOpenPackage.handle(PackageState.new(package_id()), night)

      ada = %{open.(operator_actor("ada")) | home_crew: "night"}

      assert {:error, :not_home_crew} =
               MaybeOpenPackage.handle(PackageState.new(package_id()), ada)
    end
  end

  describe "posting work is open to every crew" do
    test "an agent of another crew queues, comments on, tags and links a card" do
      eve = operator_actor("eve")
      home = card_of("home")

      queue = cmd(QueueCardV1, %{issue_ref: @ref, title: "For home", kind: "slice", by: eve})

      assert {:ok, [_]} =
               MaybeQueueCard.handle(CardState.new(card_id()), %{queue | home_crew: "home"})

      assert {:ok, [_]} =
               MaybeCommentOnCard.handle(
                 home,
                 cmd(CommentOnCardV1, %{card_id: card_id(), text: "hi", by: eve})
               )

      assert {:ok, [_]} =
               MaybeTagCard.handle(
                 home,
                 cmd(TagCardV1, %{card_id: card_id(), tag: "night", by: eve})
               )

      link =
        cmd(LinkCardV1, %{
          card_id: card_id(),
          to_card_id: IssueRef.card_id("example-org/widget#8"),
          link: "relates_to",
          by: eve
        })

      assert {:ok, [_]} = MaybeLinkCard.handle(home, link)
    end
  end

  describe "claiming and crew lanes" do
    test "an unreserved card on another crew's board may be claimed" do
      assert claimed(card_of("home"), "eve").holder == "eve"
    end

    test "a lane reserved for a crew is claimed by that crew's agents only" do
      reserve =
        cmd(ReserveCardV1, %{card_id: card_id(), crew: "night", by: operator_actor("bob")})

      in_night = run(card_of("home"), MaybeReserveCard, reserve)

      assert in_night.lane_crew == "night"
      assert in_night.lane_node_id == nil

      assert {:error, :other_crew_lane} =
               MaybeClaimCard.handle(
                 in_night,
                 cmd(ClaimCardV1, %{card_id: card_id(), by: operator_actor("cyd")})
               )

      assert claimed(in_night, "eve").holder == "eve"
    end

    test "an agent's lane stays that agent's, whatever its crew" do
      reserve =
        cmd(ReserveCardV1, %{
          card_id: card_id(),
          lane: "eve",
          lane_node_id: hex("eve"),
          by: operator_actor("bob")
        })

      in_eves = run(card_of("home"), MaybeReserveCard, reserve)

      assert {:error, :not_in_lane} =
               MaybeClaimCard.handle(
                 in_eves,
                 cmd(ClaimCardV1, %{card_id: card_id(), by: operator_actor("cyd")})
               )

      assert claimed(in_eves, "eve").holder == "eve"
    end

    test "lifting a crew lane opens the card again" do
      reserve = cmd(ReserveCardV1, %{card_id: card_id(), crew: "night", by: Actor.owner()})
      lift = cmd(LiftCardReservationV1, %{card_id: card_id(), by: Actor.owner()})

      lifted =
        card_of("home") |> run(MaybeReserveCard, reserve) |> run(MaybeLiftCardReservation, lift)

      assert lifted.lane_crew == nil
      assert claimed(lifted, "cyd").holder == "cyd"
    end

    test "a reservation names a lane or a crew, never both, never neither" do
      assert {:error, :one_lane} =
               ReserveCardV1.new(%{
                 card_id: card_id(),
                 lane: "cyd",
                 crew: "night",
                 by: Actor.owner()
               })

      assert {:error, :missing_required_fields} =
               ReserveCardV1.new(%{card_id: card_id(), by: Actor.owner()})

      assert {:error, :invalid_crew} =
               ReserveCardV1.new(%{card_id: card_id(), crew: "no spaces", by: Actor.owner()})
    end
  end

  describe "holder rules are unchanged across crews" do
    test "a holder from another crew blocks, releases and finishes the card it holds" do
      eve = operator_actor("eve")
      held = claimed(card_of("home"), "eve")

      assert {:ok, [_]} =
               MaybeBlockCard.handle(
                 held,
                 cmd(BlockCardV1, %{card_id: card_id(), reason: "wait", by: eve})
               )

      assert {:ok, [_]} =
               MaybeReleaseCard.handle(
                 held,
                 cmd(ReleaseCardV1, %{card_id: card_id(), reason: "drop", by: eve})
               )

      assert {:ok, [%{status: status}]} =
               MaybeFinishCard.handle(
                 held,
                 cmd(FinishCardV1, %{card_id: card_id(), result: "done", by: eve})
               )

      assert CardStatus.has?(status, CardStatus.finished())
    end
  end

  describe "steering a held or blocked card belongs to the home crew (r1)" do
    # A card on night's board, held by eve and blocked by her; home's
    # supervisor may not release, block or unblock it, night's operator may.
    defp held_on_night, do: claimed(card_of("night"), "eve")

    defp blocked_on_night do
      run(
        held_on_night(),
        MaybeBlockCard,
        cmd(BlockCardV1, %{card_id: card_id(), reason: "wait", by: Actor.owner()})
      )
    end

    test "another crew's supervisor is refused not_home_crew; the home crew's operator may" do
      release = &cmd(ReleaseCardV1, %{card_id: card_id(), reason: "drop", by: &1})
      block = &cmd(BlockCardV1, %{card_id: card_id(), reason: "wait", by: &1})
      unblock = &cmd(UnblockCardV1, %{card_id: card_id(), by: &1})
      ada = operator_actor("ada")

      assert {:error, :not_home_crew} = MaybeReleaseCard.handle(held_on_night(), release.(ada))
      assert {:error, :not_home_crew} = MaybeBlockCard.handle(held_on_night(), block.(ada))
      assert {:error, :not_home_crew} = MaybeUnblockCard.handle(blocked_on_night(), unblock.(ada))

      held_by_cyd = claimed(card_of("night"), "cyd")
      eve = operator_actor("eve")
      assert {:ok, [_]} = MaybeReleaseCard.handle(held_by_cyd, release.(eve))
      assert {:ok, [_]} = MaybeBlockCard.handle(held_by_cyd, block.(eve))
    end

    test "a plain agent who does not hold the card is still told not_holder" do
      release =
        cmd(ReleaseCardV1, %{card_id: card_id(), reason: "drop", by: operator_actor("cyd")})

      assert {:error, :not_holder} = MaybeReleaseCard.handle(held_on_night(), release)
    end

    test "an unheld blocked card in a crew's lane is unblocked by that crew only (b1)" do
      reserve = cmd(ReserveCardV1, %{card_id: card_id(), crew: "night", by: Actor.owner()})
      block = cmd(BlockCardV1, %{card_id: card_id(), reason: "wait", by: Actor.owner()})
      unheld = card_of("home") |> run(MaybeReserveCard, reserve) |> run(MaybeBlockCard, block)
      unblock = &cmd(UnblockCardV1, %{card_id: card_id(), by: &1})

      assert {:error, :other_crew_lane} =
               MaybeUnblockCard.handle(unheld, unblock.(operator_actor("cyd")))

      assert {:ok, [_]} = MaybeUnblockCard.handle(unheld, unblock.(operator_actor("eve")))
    end
  end

  describe "handing a board over to another crew (r2)" do
    test "the owner hands a board over; its cards and packages follow it" do
      hand = cmd(HandOverBoardV1, %{repo: @repo, crew: "night", by: Actor.owner()})
      handed = run(board_of("home"), MaybeHandOverBoard, hand, BoardState)
      assert handed.home_crew == "night"

      # A card queued while the board was home's is ordered by night now: the
      # board's live home crew rides on every card command.
      rank =
        cmd(PrioritiseCardV1, %{
          card_id: card_id(),
          rank: 3,
          rationale: "ours",
          by: operator_actor("eve")
        })

      payload = Map.put(PrioritiseCardV1.to_map(rank), :home_crew, "night")
      assert {:ok, [_]} = CardAggregate.execute(card_of("home"), payload)

      payload =
        Map.put(PrioritiseCardV1.to_map(%{rank | by: operator_actor("bob")}), :home_crew, "night")

      assert {:error, :not_home_crew} = CardAggregate.execute(card_of("home"), payload)
    end

    test "only the owner hands a board over, and only an open one to another crew" do
      hand = &cmd(HandOverBoardV1, %{repo: @repo, crew: &2, by: &1})

      assert {:error, :not_permitted} =
               MaybeHandOverBoard.handle(board_of("home"), hand.(operator_actor("bob"), "night"))

      assert {:error, :unknown_board} =
               MaybeHandOverBoard.handle(
                 BoardState.new(IssueRef.board_id(@repo)),
                 hand.(Actor.owner(), "night")
               )

      assert {:error, :already_home_crew} =
               MaybeHandOverBoard.handle(board_of("night"), hand.(Actor.owner(), "night"))

      assert {:error, :invalid_crew} =
               HandOverBoardV1.new(%{repo: @repo, crew: "no spaces", by: Actor.owner()})
    end
  end

  describe "the board-wide prioritiser" do
    test "only the owner discharges it, even when it is enlisted in an operator's crew" do
      # pia moves into night: night's operator would otherwise take the
      # owner's appointment away.
      crew =
        CrewState.apply_event(crews(), %{
          event_type: "agent_enlisted_v1",
          node_id: hex("pia"),
          name: "pia",
          crew: "night"
        })

      {:ok, eve} = Actor.from_crew(crew, node_id("eve"))
      discharge = &cmd(DischargeAgentV1, %{name: "pia", by: &1})

      assert {:error, :appointed_by_owner} = MaybeDischargeAgent.handle(crew, discharge.(eve))
      assert {:ok, [_]} = MaybeDischargeAgent.handle(crew, discharge.(Actor.owner()))
    end
  end
end
