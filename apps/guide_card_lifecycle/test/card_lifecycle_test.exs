defmodule GuideCardLifecycle.CardLifecycleTest do
  # Every card desk's rule, pure: the command, the state and who acts. The
  # role a caller holds comes from the crew (see RoleGateTest); here each
  # rule is checked against the actors that may and may not use it.
  use ExUnit.Case, async: true

  import GuideCardLifecycle.TestCrew

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CardAggregate
  alias GuideCardLifecycle.CardState
  alias GuideCardLifecycle.CardStatus
  alias GuideCardLifecycle.IssueRef

  alias GuideCardLifecycle.BlockCard.{BlockCardV1, MaybeBlockCard}
  alias GuideCardLifecycle.ClaimCard.{ClaimCardV1, MaybeClaimCard}
  alias GuideCardLifecycle.CommentOnCard.{CommentOnCardV1, MaybeCommentOnCard}
  alias GuideCardLifecycle.FinishCard.{FinishCardV1, MaybeFinishCard}
  alias GuideCardLifecycle.LiftCardReservation.{LiftCardReservationV1, MaybeLiftCardReservation}
  alias GuideCardLifecycle.LinkCard.{LinkCardV1, MaybeLinkCard}
  alias GuideCardLifecycle.PrioritiseCard.{MaybePrioritiseCard, PrioritiseCardV1}
  alias GuideCardLifecycle.QueueCard.{MaybeQueueCard, QueueCardV1}
  alias GuideCardLifecycle.ReclassifyCard.{MaybeReclassifyCard, ReclassifyCardV1}
  alias GuideCardLifecycle.ReleaseCard.{MaybeReleaseCard, ReleaseCardV1}
  alias GuideCardLifecycle.ReserveCard.{MaybeReserveCard, ReserveCardV1}
  alias GuideCardLifecycle.RewordCard.{MaybeRewordCard, RewordCardV1}
  alias GuideCardLifecycle.TagCard.{MaybeTagCard, TagCardV1}
  alias GuideCardLifecycle.UnblockCard.{MaybeUnblockCard, UnblockCardV1}
  alias GuideCardLifecycle.UnlinkCard.{MaybeUnlinkCard, UnlinkCardV1}
  alias GuideCardLifecycle.UnpinCard.{MaybeUnpinCard, UnpinCardV1}
  alias GuideCardLifecycle.UntagCard.{MaybeUntagCard, UntagCardV1}
  alias GuideCardLifecycle.WithdrawCard.{MaybeWithdrawCard, WithdrawCardV1}

  @ref "example-org/widget#7"
  @other "example-org/widget#8"

  defp card_id, do: IssueRef.card_id(@ref)
  defp other_id, do: IssueRef.card_id(@other)

  defp queue_cmd(by \\ actor("bob")) do
    {:ok, cmd} =
      QueueCardV1.new(%{
        issue_ref: @ref,
        title: "Draw the board",
        kind: "slice",
        story: %{role: "agent", ask: "a board", value: "I know what is next"},
        tags: ["ui", "mesh"],
        by: by
      })

    cmd
  end

  defp queued do
    {:ok, events} = MaybeQueueCard.handle(CardState.new(card_id()), queue_cmd())
    fold(CardState.new(card_id()), events)
  end

  defp fold(state, events), do: Enum.reduce(events, state, &CardState.apply_event(&2, &1))

  defp run(state, module, cmd) do
    {:ok, events} = module.handle(state, cmd)
    fold(state, events)
  end

  defp cmd(module, fields) do
    {:ok, cmd} = module.new(fields)
    cmd
  end

  defp claimed_by(name) do
    run(queued(), MaybeClaimCard, cmd(ClaimCardV1, %{card_id: card_id(), by: actor(name)}))
  end

  describe "queue_card" do
    test "any agent queues a card for an issue, unranked, with its story and tags" do
      {:ok, [event]} = MaybeQueueCard.handle(CardState.new(card_id()), queue_cmd())

      assert %{
               event_type: "card_queued_v1",
               card_id: id,
               issue_ref: @ref,
               repo: "example-org/widget",
               title: "Draw the board",
               kind: "slice",
               tags: ["ui", "mesh"],
               by: "bob"
             } = event

      assert id == card_id()
      state = queued()
      assert CardStatus.state_name(state.status) == "queued"
      assert state.rank == nil
      assert state.story == %{role: "agent", ask: "a board", value: "I know what is next"}
    end

    test "the supervisor and the owner queue too" do
      for by <- [actor("ada"), Actor.owner()] do
        assert {:ok, [_]} = MaybeQueueCard.handle(CardState.new(card_id()), queue_cmd(by))
      end
    end

    test "a second card for the same issue is refused" do
      assert {:error, :already_on_board} = MaybeQueueCard.handle(queued(), queue_cmd())
    end

    test "the command refuses a bad issue ref, an unknown kind, an empty title" do
      base = %{issue_ref: @ref, title: "t", kind: "bug", by: actor("bob")}

      assert {:error, :invalid_issue_ref} = QueueCardV1.new(%{base | issue_ref: "nope"})
      assert {:error, :invalid_kind} = QueueCardV1.new(%{base | kind: "epic"})
      assert {:error, :title_required} = QueueCardV1.new(%{base | title: ""})

      assert {:error, :invalid_story} =
               QueueCardV1.new(Map.put(base, :story, %{role: "agent", ask: ""}))
    end

    test "the card id is derived from the issue, the board from its repo" do
      cmd = queue_cmd()
      assert cmd.card_id == card_id()
      assert cmd.board_id == IssueRef.board_id("example-org/widget")
    end
  end

  describe "claim_card" do
    test "an enlisted agent claims a queued card and becomes its holder" do
      state = claimed_by("bob")
      assert CardStatus.state_name(state.status) == "claimed"
      assert state.holder == "bob"
      assert state.holder_node_id == hex("bob")
      assert is_integer(state.claimed_at)
    end

    test "a claimed card is refused to the next claimant" do
      cmd = cmd(ClaimCardV1, %{card_id: card_id(), by: actor("cyd")})
      assert {:error, :already_claimed} = MaybeClaimCard.handle(claimed_by("bob"), cmd)
    end

    test "the owner never claims: a holder is an agent" do
      cmd = cmd(ClaimCardV1, %{card_id: card_id(), by: Actor.owner()})
      assert {:error, :not_permitted} = MaybeClaimCard.handle(queued(), cmd)
    end

    test "a reserved card is claimed only in its lane" do
      reserved =
        run(
          queued(),
          MaybeReserveCard,
          cmd(ReserveCardV1, %{
            card_id: card_id(),
            lane: "cyd",
            lane_node_id: hex("cyd"),
            by: actor("ada")
          })
        )

      assert reserved.lane == "cyd"

      bob = cmd(ClaimCardV1, %{card_id: card_id(), by: actor("bob")})
      assert {:error, :not_in_lane} = MaybeClaimCard.handle(reserved, bob)

      cyd = cmd(ClaimCardV1, %{card_id: card_id(), by: actor("cyd")})

      assert {:ok, [%{event_type: "card_claimed_v1", holder: "cyd"}]} =
               MaybeClaimCard.handle(reserved, cyd)
    end

    test "a blocked card cannot be claimed" do
      blocked =
        run(
          queued(),
          MaybeBlockCard,
          cmd(BlockCardV1, %{card_id: card_id(), reason: "waits on #8", by: actor("ada")})
        )

      cmd = cmd(ClaimCardV1, %{card_id: card_id(), by: actor("bob")})
      assert {:error, :blocked} = MaybeClaimCard.handle(blocked, cmd)
    end
  end

  describe "release, block, unblock, finish" do
    test "the holder releases with a reason; the card is back in the queue" do
      released =
        run(
          claimed_by("bob"),
          MaybeReleaseCard,
          cmd(ReleaseCardV1, %{card_id: card_id(), reason: "out of time", by: actor("bob")})
        )

      assert CardStatus.state_name(released.status) == "queued"
      assert released.holder == nil
    end

    test "the supervisor releases a stale claim; another agent may not" do
      sup = cmd(ReleaseCardV1, %{card_id: card_id(), reason: "stale", by: actor("ada")})
      assert {:ok, [_]} = MaybeReleaseCard.handle(claimed_by("bob"), sup)

      cyd = cmd(ReleaseCardV1, %{card_id: card_id(), reason: "mine now", by: actor("cyd")})
      assert {:error, :not_holder} = MaybeReleaseCard.handle(claimed_by("bob"), cyd)
    end

    test "release needs a claim and a reason" do
      cmd = cmd(ReleaseCardV1, %{card_id: card_id(), reason: "x", by: actor("ada")})
      assert {:error, :not_claimed} = MaybeReleaseCard.handle(queued(), cmd)

      assert {:error, :reason_required} =
               ReleaseCardV1.new(%{card_id: card_id(), reason: "", by: actor("bob")})
    end

    test "the holder blocks and unblocks; the card returns to claimed" do
      blocked =
        run(
          claimed_by("bob"),
          MaybeBlockCard,
          cmd(BlockCardV1, %{card_id: card_id(), reason: "needs #8", by: actor("bob")})
        )

      assert CardStatus.state_name(blocked.status) == "blocked"

      again = cmd(BlockCardV1, %{card_id: card_id(), reason: "x", by: actor("bob")})
      assert {:error, :already_blocked} = MaybeBlockCard.handle(blocked, again)

      unblocked =
        run(
          blocked,
          MaybeUnblockCard,
          cmd(UnblockCardV1, %{card_id: card_id(), by: actor("bob")})
        )

      assert CardStatus.state_name(unblocked.status) == "claimed"
      assert unblocked.holder == "bob"

      not_blocked = cmd(UnblockCardV1, %{card_id: card_id(), by: actor("bob")})
      assert {:error, :not_blocked} = MaybeUnblockCard.handle(unblocked, not_blocked)
    end

    test "another agent may not block someone else's card" do
      cmd = cmd(BlockCardV1, %{card_id: card_id(), reason: "x", by: actor("cyd")})
      assert {:error, :not_holder} = MaybeBlockCard.handle(claimed_by("bob"), cmd)
    end

    test "only the holder finishes, with a one-line result" do
      cyd = cmd(FinishCardV1, %{card_id: card_id(), result: "done", by: actor("cyd")})
      assert {:error, :not_holder} = MaybeFinishCard.handle(claimed_by("bob"), cyd)

      sup = cmd(FinishCardV1, %{card_id: card_id(), result: "done", by: actor("ada")})
      assert {:error, :not_holder} = MaybeFinishCard.handle(claimed_by("bob"), sup)

      owner = cmd(FinishCardV1, %{card_id: card_id(), result: "done", by: Actor.owner()})
      assert {:error, :not_holder} = MaybeFinishCard.handle(claimed_by("bob"), owner)

      bob = cmd(FinishCardV1, %{card_id: card_id(), result: "shipped v0.1.0", by: actor("bob")})
      finished = run(claimed_by("bob"), MaybeFinishCard, bob)
      assert CardStatus.state_name(finished.status) == "finished"

      assert {:error, :result_required} =
               FinishCardV1.new(%{card_id: card_id(), result: "", by: actor("bob")})
    end

    test "a finished card refuses further work but still takes comments and links" do
      finished =
        run(
          claimed_by("bob"),
          MaybeFinishCard,
          cmd(FinishCardV1, %{card_id: card_id(), result: "done", by: actor("bob")})
        )

      claim = cmd(ClaimCardV1, %{card_id: card_id(), by: actor("cyd")})
      assert {:error, :finished} = CardAggregate.execute(finished, ClaimCardV1.to_payload(claim))

      comment = cmd(CommentOnCardV1, %{card_id: card_id(), text: "nice", by: actor("cyd")})
      assert {:ok, [_]} = CardAggregate.execute(finished, CommentOnCardV1.to_payload(comment))
    end
  end

  describe "withdraw" do
    test "the supervisor or the owner withdraws; an agent may not" do
      for by <- [actor("ada"), Actor.owner()] do
        cmd = cmd(WithdrawCardV1, %{card_id: card_id(), reason: "duplicate", by: by})

        assert {:ok, [%{event_type: "card_withdrawn_v1"}]} =
                 MaybeWithdrawCard.handle(queued(), cmd)
      end

      bob = cmd(WithdrawCardV1, %{card_id: card_id(), reason: "x", by: actor("bob")})
      assert {:error, :not_permitted} = MaybeWithdrawCard.handle(queued(), bob)
    end

    test "a withdrawn card refuses a claim" do
      withdrawn =
        run(
          queued(),
          MaybeWithdrawCard,
          cmd(WithdrawCardV1, %{card_id: card_id(), reason: "dup", by: actor("ada")})
        )

      claim = cmd(ClaimCardV1, %{card_id: card_id(), by: actor("bob")})

      assert {:error, :withdrawn} =
               CardAggregate.execute(withdrawn, ClaimCardV1.to_payload(claim))
    end
  end

  describe "prioritise and unpin" do
    test "the prioritiser ranks with a rationale" do
      cmd =
        cmd(PrioritiseCardV1, %{
          card_id: card_id(),
          rank: 10,
          rationale: "unblocks two",
          by: actor("pia")
        })

      ranked = run(queued(), MaybePrioritiseCard, cmd)
      assert ranked.rank == 10
      assert ranked.rationale == "unblocks two"
      refute CardStatus.pinned?(ranked.status)
    end

    test "an owner rank pins the card, and the prioritiser cannot change it" do
      owner =
        cmd(PrioritiseCardV1, %{card_id: card_id(), rank: 1, rationale: "", by: Actor.owner()})

      pinned = run(queued(), MaybePrioritiseCard, owner)
      assert CardStatus.pinned?(pinned.status)
      assert pinned.ranked_by == "owner"

      pia =
        cmd(PrioritiseCardV1, %{
          card_id: card_id(),
          rank: 50,
          rationale: "later",
          by: actor("pia")
        })

      assert {:error, :pinned_by_owner} = MaybePrioritiseCard.handle(pinned, pia)

      unpinned =
        run(pinned, MaybeUnpinCard, cmd(UnpinCardV1, %{card_id: card_id(), by: Actor.owner()}))

      refute CardStatus.pinned?(unpinned.status)
      assert {:ok, [_]} = MaybePrioritiseCard.handle(unpinned, pia)
    end

    test "nobody else ranks, and only the owner unpins" do
      for name <- ~w(ada bob) do
        cmd =
          cmd(PrioritiseCardV1, %{card_id: card_id(), rank: 3, rationale: "r", by: actor(name)})

        assert {:error, :not_permitted} = MaybePrioritiseCard.handle(queued(), cmd)
      end

      pia = cmd(UnpinCardV1, %{card_id: card_id(), by: actor("pia")})
      assert {:error, :not_permitted} = MaybeUnpinCard.handle(queued(), pia)

      owner = cmd(UnpinCardV1, %{card_id: card_id(), by: Actor.owner()})
      assert {:error, :not_pinned} = MaybeUnpinCard.handle(queued(), owner)
    end

    test "the prioritiser must give a rationale; a rank is a non-negative integer" do
      assert {:error, :rationale_required} =
               PrioritiseCardV1.new(%{
                 card_id: card_id(),
                 rank: 2,
                 rationale: "",
                 by: actor("pia")
               })

      assert {:error, :invalid_rank} =
               PrioritiseCardV1.new(%{
                 card_id: card_id(),
                 rank: -1,
                 rationale: "r",
                 by: actor("pia")
               })

      assert {:error, :invalid_rank} =
               PrioritiseCardV1.new(%{
                 card_id: card_id(),
                 rank: "1",
                 rationale: "r",
                 by: actor("pia")
               })
    end
  end

  describe "reserve and lift" do
    test "supervisor, prioritiser and owner reserve; a plain agent may not" do
      for by <- [actor("ada"), actor("pia"), Actor.owner()] do
        cmd =
          cmd(ReserveCardV1, %{card_id: card_id(), lane: "bob", lane_node_id: hex("bob"), by: by})

        assert {:ok, [%{event_type: "card_reserved_v1", lane: "bob"}]} =
                 MaybeReserveCard.handle(queued(), cmd)
      end

      cmd =
        cmd(ReserveCardV1, %{
          card_id: card_id(),
          lane: "bob",
          lane_node_id: hex("bob"),
          by: actor("cyd")
        })

      assert {:error, :not_permitted} = MaybeReserveCard.handle(queued(), cmd)
    end

    test "lifting needs a reservation" do
      lift = cmd(LiftCardReservationV1, %{card_id: card_id(), by: actor("ada")})
      assert {:error, :not_reserved} = MaybeLiftCardReservation.handle(queued(), lift)

      reserved =
        run(
          queued(),
          MaybeReserveCard,
          cmd(ReserveCardV1, %{
            card_id: card_id(),
            lane: "bob",
            lane_node_id: hex("bob"),
            by: actor("ada")
          })
        )

      lifted = run(reserved, MaybeLiftCardReservation, lift)
      assert lifted.lane == nil
      assert lifted.lane_node_id == nil
    end
  end

  describe "reword and reclassify" do
    test "supervisor, owner and holder reword; another agent may not" do
      cmd = fn by -> cmd(RewordCardV1, %{card_id: card_id(), title: "Better title", by: by}) end
      state = claimed_by("bob")

      for by <- [actor("ada"), Actor.owner(), actor("bob")] do
        assert {:ok, [%{event_type: "card_reworded_v1", title: "Better title"}]} =
                 MaybeRewordCard.handle(state, cmd.(by))
      end

      assert {:error, :not_permitted} = MaybeRewordCard.handle(state, cmd.(actor("cyd")))
    end

    test "supervisor and owner reclassify, to a known kind" do
      cmd = fn by -> cmd(ReclassifyCardV1, %{card_id: card_id(), kind: "bug", by: by}) end
      changed = run(queued(), MaybeReclassifyCard, cmd.(actor("ada")))
      assert changed.kind == "bug"
      assert {:error, :not_permitted} = MaybeReclassifyCard.handle(queued(), cmd.(actor("bob")))

      assert {:error, :invalid_kind} =
               ReclassifyCardV1.new(%{card_id: card_id(), kind: "epic", by: actor("ada")})
    end
  end

  describe "tags, links, comments" do
    test "any agent tags and untags; a tag is held once" do
      tagged =
        run(
          queued(),
          MaybeTagCard,
          cmd(TagCardV1, %{card_id: card_id(), tag: "infra", by: actor("cyd")})
        )

      assert "infra" in tagged.tags

      again = cmd(TagCardV1, %{card_id: card_id(), tag: "infra", by: actor("bob")})
      assert {:error, :already_tagged} = MaybeTagCard.handle(tagged, again)

      untagged =
        run(
          tagged,
          MaybeUntagCard,
          cmd(UntagCardV1, %{card_id: card_id(), tag: "infra", by: actor("bob")})
        )

      refute "infra" in untagged.tags
      gone = cmd(UntagCardV1, %{card_id: card_id(), tag: "infra", by: actor("bob")})
      assert {:error, :not_tagged} = MaybeUntagCard.handle(untagged, gone)
    end

    test "a link names the other card and its kind; it is stored once, on the source" do
      link =
        cmd(LinkCardV1, %{
          card_id: card_id(),
          to_card_id: other_id(),
          link: "blocks",
          by: actor("bob")
        })

      linked = run(queued(), MaybeLinkCard, link)
      assert linked.links == [%{to_card_id: other_id(), link: "blocks"}]
      assert {:error, :already_linked} = MaybeLinkCard.handle(linked, link)

      unlink =
        cmd(UnlinkCardV1, %{
          card_id: card_id(),
          to_card_id: other_id(),
          link: "blocks",
          by: actor("bob")
        })

      unlinked = run(linked, MaybeUnlinkCard, unlink)
      assert unlinked.links == []
      assert {:error, :not_linked} = MaybeUnlinkCard.handle(unlinked, unlink)
    end

    test "a link kind is blocks, relates_to or follows_up, and never to itself" do
      assert {:error, :invalid_link} =
               LinkCardV1.new(%{
                 card_id: card_id(),
                 to_card_id: other_id(),
                 link: "owns",
                 by: actor("bob")
               })

      assert {:error, :self_link} =
               LinkCardV1.new(%{
                 card_id: card_id(),
                 to_card_id: card_id(),
                 link: "blocks",
                 by: actor("bob")
               })

      assert {:error, :invalid_card_id} =
               LinkCardV1.new(%{
                 card_id: card_id(),
                 to_card_id: "nope",
                 link: "blocks",
                 by: actor("bob")
               })
    end

    test "a comment carries a fresh id, its author and the text; the count follows" do
      cmd = cmd(CommentOnCardV1, %{card_id: card_id(), text: "picked this up", by: actor("cyd")})
      assert :ok = :reckon_gater_stream_id.validate("comment-" <> cmd.comment_id)

      {:ok, [event]} = MaybeCommentOnCard.handle(queued(), cmd)
      assert %{event_type: "card_commented_v1", text: "picked this up", by: "cyd"} = event
      assert event.comment_id == cmd.comment_id
      assert fold(queued(), [event]).comment_count == 1

      assert {:error, :text_required} =
               CommentOnCardV1.new(%{card_id: card_id(), text: "", by: actor("cyd")})
    end
  end

  test "every desk refuses a card that was never queued" do
    claim = cmd(ClaimCardV1, %{card_id: card_id(), by: actor("bob")})

    assert {:error, :unknown_card} =
             CardAggregate.execute(CardState.new(card_id()), ClaimCardV1.to_payload(claim))
  end

  test "the state folds an event as evoq delivers it, inside an envelope" do
    {:ok, [event]} = MaybeQueueCard.handle(CardState.new(card_id()), queue_cmd())

    state =
      CardState.apply_event(CardState.new(card_id()), %{event_type: event.event_type, data: event})

    assert state.title == "Draw the board"
  end
end
