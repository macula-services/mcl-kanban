defmodule GuideCardLifecycle.PackageTest do
  # A work package is a GitHub issue labelled work-package: the supervisor (or
  # the owner) opens it, the prioritiser ranks packages on their own scale, an
  # owner rank pins, and cards are filed into a package and out of it again.
  use ExUnit.Case, async: true

  import GuideCardLifecycle.TestCrew

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CardState
  alias GuideCardLifecycle.IssueRef
  alias GuideCardLifecycle.PackageState

  alias GuideCardLifecycle.FileCard.{FileCardV1, MaybeFileCard}
  alias GuideCardLifecycle.OpenPackage.{MaybeOpenPackage, OpenPackageV1}
  alias GuideCardLifecycle.PrioritisePackage.{MaybePrioritisePackage, PrioritisePackageV1}
  alias GuideCardLifecycle.QueueCard.{MaybeQueueCard, QueueCardV1}
  alias GuideCardLifecycle.UnfileCard.{MaybeUnfileCard, UnfileCardV1}
  alias GuideCardLifecycle.UnpinPackage.{MaybeUnpinPackage, UnpinPackageV1}

  @package "example-org/widget#1"
  @card "example-org/gadget#7"

  defp fold(state, events, module), do: Enum.reduce(events, state, &module.apply_event(&2, &1))

  defp cmd(module, fields) do
    {:ok, cmd} = module.new(fields)
    cmd
  end

  defp open_cmd(by \\ actor("ada")),
    do: cmd(OpenPackageV1, %{issue_ref: @package, title: "Ship the widget", by: by})

  defp opened do
    {:ok, events} =
      MaybeOpenPackage.handle(PackageState.new(IssueRef.package_id(@package)), open_cmd())

    fold(PackageState.new(IssueRef.package_id(@package)), events, PackageState)
  end

  defp rank_cmd(by, rank, rationale \\ "first things first"),
    do:
      cmd(PrioritisePackageV1, %{
        package_id: IssueRef.package_id(@package),
        rank: rank,
        rationale: rationale,
        by: by
      })

  defp run(state, desk, cmd, module) do
    {:ok, events} = desk.handle(state, cmd)
    fold(state, events, module)
  end

  defp queued_card do
    queue =
      cmd(QueueCardV1, %{issue_ref: @card, title: "A gadget", kind: "slice", by: actor("bob")})

    {:ok, events} = MaybeQueueCard.handle(CardState.new(queue.card_id), queue)
    fold(CardState.new(queue.card_id), events, CardState)
  end

  describe "open_package" do
    test "the supervisor opens a package for a work-package issue" do
      cmd = open_cmd()
      assert cmd.package_id == IssueRef.package_id(@package)
      assert String.starts_with?(cmd.package_id, "package-")

      assert {:ok,
              [
                %{
                  event_type: "package_opened_v1",
                  package_id: id,
                  issue_ref: @package,
                  title: "Ship the widget",
                  by: "ada"
                }
              ]} = MaybeOpenPackage.handle(PackageState.new(cmd.package_id), cmd)

      assert id == cmd.package_id
    end

    test "the owner opens one too; a plain agent and the prioritiser may not" do
      assert {:ok, [_]} = MaybeOpenPackage.handle(PackageState.new("p"), open_cmd(Actor.owner()))

      for name <- ["bob", "pia"] do
        assert {:error, :not_permitted} =
                 MaybeOpenPackage.handle(PackageState.new("p"), open_cmd(actor(name))),
               name
      end
    end

    test "a package is opened once" do
      assert {:error, :already_open} = MaybeOpenPackage.handle(opened(), open_cmd())
    end

    test "a package names an issue and has a title" do
      assert {:error, :invalid_issue_ref} =
               OpenPackageV1.new(%{issue_ref: "widget#1", title: "t", by: actor("ada")})

      assert {:error, :title_required} =
               OpenPackageV1.new(%{issue_ref: @package, title: " ", by: actor("ada")})
    end
  end

  describe "prioritise_package" do
    test "the prioritiser ranks an open package, with a rationale" do
      ranked = run(opened(), MaybePrioritisePackage, rank_cmd(actor("pia"), 2), PackageState)
      assert ranked.rank == 2
      assert ranked.rationale == "first things first"
      refute PackageState.pinned?(ranked)
    end

    test "the prioritiser must say why; the owner may not" do
      assert {:error, :rationale_required} =
               PrioritisePackageV1.new(%{package_id: "p", rank: 1, by: actor("pia")})

      assert {:ok, _} = PrioritisePackageV1.new(%{package_id: "p", rank: 1, by: Actor.owner()})
    end

    test "an owner rank pins, and the prioritiser cannot move a pinned package" do
      pinned =
        run(opened(), MaybePrioritisePackage, rank_cmd(Actor.owner(), 0, nil), PackageState)

      assert PackageState.pinned?(pinned)

      assert {:error, :pinned_by_owner} =
               MaybePrioritisePackage.handle(pinned, rank_cmd(actor("pia"), 4))

      assert {:ok, _} = MaybePrioritisePackage.handle(pinned, rank_cmd(Actor.owner(), 4, nil))
    end

    test "only the prioritiser and the owner rank, and only an open package" do
      for name <- ["ada", "bob"] do
        assert {:error, :not_permitted} =
                 MaybePrioritisePackage.handle(opened(), rank_cmd(actor(name), 1)),
               name
      end

      assert {:error, :unknown_package} =
               MaybePrioritisePackage.handle(PackageState.new("p"), rank_cmd(actor("pia"), 1))
    end

    test "a rank is a whole number, 0 or more" do
      for bad <- [-1, 1.5, "1", nil] do
        assert {:error, :invalid_rank} =
                 PrioritisePackageV1.new(%{
                   package_id: "p",
                   rank: bad,
                   rationale: "r",
                   by: actor("pia")
                 }),
               inspect(bad)
      end
    end
  end

  describe "unpin_package" do
    test "only the owner unpins, and only a pinned package" do
      pinned =
        run(opened(), MaybePrioritisePackage, rank_cmd(Actor.owner(), 0, nil), PackageState)

      unpin = cmd(UnpinPackageV1, %{package_id: IssueRef.package_id(@package), by: Actor.owner()})

      unpinned = run(pinned, MaybeUnpinPackage, unpin, PackageState)
      refute PackageState.pinned?(unpinned)
      assert unpinned.rank == 0
      assert {:error, :not_pinned} = MaybeUnpinPackage.handle(unpinned, unpin)

      by_pia = cmd(UnpinPackageV1, %{package_id: IssueRef.package_id(@package), by: actor("pia")})
      assert {:error, :not_permitted} = MaybeUnpinPackage.handle(pinned, by_pia)
    end
  end

  describe "file_card and unfile_card" do
    defp file_cmd(by \\ actor("ada")),
      do: cmd(FileCardV1, %{card_id: IssueRef.card_id(@card), package_ref: @package, by: by})

    defp unfile_cmd(by \\ actor("ada")),
      do: cmd(UnfileCardV1, %{card_id: IssueRef.card_id(@card), by: by})

    test "the supervisor files a card into a package, from any repo" do
      assert {:ok, [%{event_type: "card_filed_v1", work_package: @package, by: "ada"}]} =
               MaybeFileCard.handle(queued_card(), file_cmd())

      filed = run(queued_card(), MaybeFileCard, file_cmd(), CardState)
      assert filed.work_package == @package
      assert filed.status == queued_card().status
    end

    test "the owner files too; a plain agent and the prioritiser may not" do
      assert {:ok, [_]} = MaybeFileCard.handle(queued_card(), file_cmd(Actor.owner()))

      for name <- ["bob", "pia"] do
        assert {:error, :not_permitted} =
                 MaybeFileCard.handle(queued_card(), file_cmd(actor(name)))
      end
    end

    test "a card already in that package is refused; another package refiles it" do
      filed = run(queued_card(), MaybeFileCard, file_cmd(), CardState)
      assert {:error, :already_filed} = MaybeFileCard.handle(filed, file_cmd())

      other =
        cmd(FileCardV1, %{
          card_id: IssueRef.card_id(@card),
          package_ref: "example-org/widget#2",
          by: actor("ada")
        })

      assert {:ok, [%{work_package: "example-org/widget#2"}]} = MaybeFileCard.handle(filed, other)
    end

    test "unfiling takes a filed card out of its package" do
      filed = run(queued_card(), MaybeFileCard, file_cmd(), CardState)
      unfiled = run(filed, MaybeUnfileCard, unfile_cmd(), CardState)
      assert unfiled.work_package == nil
      assert {:error, :not_filed} = MaybeUnfileCard.handle(unfiled, unfile_cmd())
      assert {:error, :not_permitted} = MaybeUnfileCard.handle(filed, unfile_cmd(actor("bob")))
    end

    test "a package reference must read owner/repo#n" do
      assert {:error, :invalid_issue_ref} =
               FileCardV1.new(%{
                 card_id: IssueRef.card_id(@card),
                 package_ref: "nope",
                 by: actor("ada")
               })
    end
  end
end
