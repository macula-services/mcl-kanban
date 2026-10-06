defmodule MclKanbanWeb.OwnerActions do
  # What the owner does from the UI, through the same desks the mesh uses,
  # acting as GuideCardLifecycle.Actor.owner(). Every owner action is recorded
  # as the owner, so the prioritiser sees where Raf overruled it.
  #
  # The UI is the owner because it listens on loopback on the box that runs
  # the board and Raf reaches it through his own tunnel (#2, section 5).
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AppointPrioritiser.{AppointPrioritiserV1, MaybeAppointPrioritiser}
  alias GuideCardLifecycle.AppointSupervisor.{AppointSupervisorV1, MaybeAppointSupervisor}
  alias GuideCardLifecycle.ArchiveBoard.{ArchiveBoardV1, MaybeArchiveBoard}
  alias GuideCardLifecycle.BlockCard.{BlockCardV1, MaybeBlockCard}
  alias GuideCardLifecycle.CommentOnCard.{CommentOnCardV1, MaybeCommentOnCard}
  alias GuideCardLifecycle.DischargeAgent.{DischargeAgentV1, MaybeDischargeAgent}
  alias GuideCardLifecycle.EnlistAgent.{EnlistAgentV1, MaybeEnlistAgent}
  alias GuideCardLifecycle.FileCard.{FileCardV1, MaybeFileCard}
  alias GuideCardLifecycle.LiftCardReservation.{LiftCardReservationV1, MaybeLiftCardReservation}
  alias GuideCardLifecycle.OpenBoard.{MaybeOpenBoard, OpenBoardV1}
  alias GuideCardLifecycle.PrioritiseCard.{MaybePrioritiseCard, PrioritiseCardV1}
  alias GuideCardLifecycle.QueueCard.{MaybeQueueCard, QueueCardV1}
  alias GuideCardLifecycle.ReclassifyCard.{MaybeReclassifyCard, ReclassifyCardV1}
  alias GuideCardLifecycle.ReleaseCard.{MaybeReleaseCard, ReleaseCardV1}
  alias GuideCardLifecycle.ReserveCard.{MaybeReserveCard, ReserveCardV1}
  alias GuideCardLifecycle.RewordCard.{MaybeRewordCard, RewordCardV1}
  alias GuideCardLifecycle.TagCard.{MaybeTagCard, TagCardV1}
  alias GuideCardLifecycle.UnblockCard.{MaybeUnblockCard, UnblockCardV1}
  alias GuideCardLifecycle.UnfileCard.{MaybeUnfileCard, UnfileCardV1}
  alias GuideCardLifecycle.UnpinCard.{MaybeUnpinCard, UnpinCardV1}
  alias GuideCardLifecycle.UntagCard.{MaybeUntagCard, UntagCardV1}
  alias GuideCardLifecycle.WithdrawCard.{MaybeWithdrawCard, WithdrawCardV1}
  alias MclKanbanWeb.LadderRank

  @type outcome :: :ok | {:error, atom()}

  @refusals %{
    already_appointed:
      {"That agent already holds this role", "Pick another agent, or leave it as it is."},
    already_archived: {"That board is already archived", "Nothing to do."},
    already_blocked:
      {"The card is already blocked", "Unblock it first to block it for another reason."},
    already_claimed:
      {"Another agent claimed the card first", "Release it from the holder if it should move."},
    already_enlisted:
      {"That node id is already enlisted", "Each agent enlists once; find it in the crew rail."},
    already_filed: {"The card is already in that package", "Nothing to do."},
    already_linked: {"Those cards are already linked that way", "Nothing to do."},
    already_on_board: {"That issue already has a card", "Search for its number to find it."},
    already_open: {"That is open already", "Nothing to do."},
    already_tagged: {"The card already has that tag", "Nothing to do."},
    blocked: {"The card is blocked", "Unblock it first."},
    board_archived: {"That board is archived", "Queue the card on an open board."},
    finished: {"The card is finished", "Only tags, links and comments change a finished card."},
    invalid_card_id: {"That is not a card", "Reload the page; the card may be gone."},
    invalid_issue_ref:
      {"An issue reads owner/repo#number", "Pick the repo, then type the issue number."},
    invalid_kind: {"A card is a bug, a slice or ui", "Pick one of the three."},
    invalid_link: {"A link blocks, relates to or follows up", "Pick one of the three."},
    invalid_name: {"A name starts with a letter", "Use letters, digits, - and _, at most 40."},
    invalid_node_id:
      {"A node id is 64 hex characters", "Paste it from the agent's first info reply."},
    invalid_package_id: {"That is not a package", "Reload the page; the package may be gone."},
    invalid_rank: {"A rank is a whole number, 0 or more", "Lower is claimed first."},
    invalid_rationale: {"The reason is too long", "Keep it under 500 characters."},
    invalid_repo: {"A repo reads owner/repo", "For example example-org/widget."},
    invalid_story:
      {"A story needs all three parts, or none",
       "Fill in role, ask and value, or clear all three."},
    invalid_tag: {"A tag is 1 to 40 characters", "Shorten it."},
    missing_required_fields:
      {"Something is missing", "Fill in every field the dialog marks as required."},
    name_reserved: {"owner is reserved", "Pick another name."},
    name_taken:
      {"Another agent has that name", "Pick another name, or discharge the old one first."},
    not_blocked: {"The card is not blocked", "Nothing to do."},
    not_claimed: {"Nobody holds the card", "Nothing to release."},
    not_enlisted: {"That node is not on the crew", "Enlist it first."},
    not_filed: {"The card is in no package", "Nothing to do."},
    not_holder: {"Only the holder can do that", "Release the card from its holder instead."},
    not_in_lane: {"The card is reserved for another agent", "Lift the reservation first."},
    not_linked: {"Those cards are not linked", "Nothing to do."},
    not_permitted: {"The owner may not do that", "Agents do this over the mesh."},
    not_pinned: {"The card is not pinned", "Nothing to do."},
    not_reserved: {"The card is reserved for nobody", "Nothing to do."},
    not_tagged: {"The card does not have that tag", "Nothing to do."},
    pinned_by_owner: {"You pinned that", "Unpin it first."},
    rationale_required: {"The prioritiser must say why", "Add a reason."},
    read_model_behind: {"Done, but the board has not caught up yet", "It shows within a second."},
    reason_required: {"This needs a reason", "Say why in a few words."},
    result_required: {"Finishing needs a result", "Say in one line what was done."},
    self_link: {"A card cannot link to itself", "Pick another card."},
    supervisor_required: {"The board needs a supervisor", "Appoint another supervisor first."},
    text_required: {"The comment is empty", "Write something."},
    title_required: {"A card needs a title", "Use the issue's title."},
    unknown_agent: {"No agent by that name", "Enlist the agent first."},
    unknown_board: {"That repo has no board", "Open the repo's board first."},
    unknown_card: {"No such card", "Reload the page; the card may be gone."},
    unknown_command: {"The board does not know that action", "Reload the page."},
    unknown_package:
      {"No open package for that issue", "The sync opens packages from work-package issues."},
    unranked_pin: {"is unranked", "Drag it into the ladder to rank and pin it in one move."},
    unranked_target: {"cannot go below an unranked card", "Rank the card above it first."},
    withdrawn: {"The card is withdrawn", "Only tags, links and comments change a withdrawn card."}
  }

  @spec enlist(map()) :: outcome()
  def enlist(p),
    do: run(EnlistAgentV1, MaybeEnlistAgent, %{name: p["name"], node_id: p["node_id"]})

  @doc "Enlist, then appoint the new agent when a role was chosen with it."
  @spec enlist_as(map()) :: outcome()
  def enlist_as(p) do
    with :ok <- enlist(p), do: appoint(p["role"], p["name"])
  end

  defp appoint("supervisor", name), do: appoint_supervisor(name)
  defp appoint("prioritiser", name), do: appoint_prioritiser(name)
  defp appoint(_agent, _name), do: :ok

  @spec discharge(String.t()) :: outcome()
  def discharge(name), do: run(DischargeAgentV1, MaybeDischargeAgent, %{name: name})

  @spec appoint_supervisor(String.t()) :: outcome()
  def appoint_supervisor(name),
    do: run(AppointSupervisorV1, MaybeAppointSupervisor, %{name: name})

  @spec appoint_prioritiser(String.t()) :: outcome()
  def appoint_prioritiser(name),
    do: run(AppointPrioritiserV1, MaybeAppointPrioritiser, %{name: name})

  @spec open_board(String.t()) :: outcome()
  def open_board(repo), do: run(OpenBoardV1, MaybeOpenBoard, %{repo: repo})

  @spec archive_board(String.t()) :: outcome()
  def archive_board(repo), do: run(ArchiveBoardV1, MaybeArchiveBoard, %{repo: repo})

  @spec queue_card(map()) :: outcome()
  def queue_card(p) do
    run(QueueCardV1, MaybeQueueCard, %{
      issue_ref: String.trim(p["issue_ref"] || ""),
      title: p["title"],
      kind: p["kind"],
      story: story(p),
      tags: tags(p["tags"])
    })
  end

  @spec rank(String.t(), String.t(), String.t()) :: outcome()
  def rank(card_id, rank, rationale) do
    case Integer.parse(String.trim(rank || "")) do
      {n, ""} ->
        run(PrioritiseCardV1, MaybePrioritiseCard, %{
          card_id: card_id,
          rank: n,
          rationale: rationale
        })

      _ ->
        {:error, :invalid_rank}
    end
  end

  def unpin(card_id), do: run(UnpinCardV1, MaybeUnpinCard, %{card_id: card_id})

  @doc "Rank a card at a whole number, as the owner (which pins it), with an optional why."
  def rank_at(card_id, rank, rationale \\ nil),
    do:
      run(PrioritiseCardV1, MaybePrioritiseCard, %{
        card_id: card_id,
        rank: rank,
        rationale: rationale
      })

  @doc """
  The owner moved a card between two neighbours on the ladder (after_id
  above it, before_id below it, nil at an edge) in a group: a package's
  issue reference or "loose" in the packages view, a repo in the repos view.
  One owner rank between the neighbours (LadderRank), which pins the card;
  in the packages view a move into another group files it there as well.
  Returns what changed and what undoes it.
  """
  @spec rerank(map(), [map()], String.t()) :: {:ok, map()} | {:error, atom()}
  def rerank(%{card_id: id, after_id: after_id, before_id: before_id, group: group}, cards, view) do
    ranks = Map.new(cards, &{&1.card_id, &1.rank})

    with %{} = card <- Enum.find(cards, &(&1.card_id == id)) || {:error, :unknown_card},
         {:ok, rank} <- LadderRank.place(Map.delete(ranks, id), after_id, before_id),
         :ok <- rank_at(id, rank),
         {:ok, moved} <- refile(card, target(view, group)) do
      {:ok,
       %{
         card_id: id,
         rank: rank,
         moved_to: moved,
         undo: %{card_id: id, rank: card.rank, pinned: card.pinned, package: card.work_package}
       }}
    end
  end

  defp target("pkg", "loose"), do: {:package, nil}
  defp target("pkg", ref), do: {:package, ref}
  defp target(_repo_view, _group), do: :same

  defp refile(_card, :same), do: {:ok, nil}
  defp refile(%{work_package: same}, {:package, same}), do: {:ok, nil}
  defp refile(card, {:package, nil}), do: with(:ok <- unfile(card.card_id), do: {:ok, "loose"})
  defp refile(card, {:package, ref}), do: with(:ok <- file(card.card_id, ref), do: {:ok, ref})

  @doc "Undo a rerank: the rank, the pin and the package the card had before."
  @spec restore(map()) :: outcome()
  def restore(%{card_id: id, rank: rank, pinned: pinned, package: package}) do
    with :ok <- rank_back(id, rank),
         :ok <- pin_back(id, rank, pinned),
         do: package_back(id, GuideCardLifecycle.CardAggregate.current(id).work_package, package)
  end

  defp rank_back(_id, nil), do: :ok
  defp rank_back(id, rank), do: rank_at(id, rank)

  # The move pinned the card; a card that was not pinned before is unpinned
  # again. A card that had no rank keeps its new one: nothing unranks a card.
  defp pin_back(id, _rank, 0), do: unpin(id)
  defp pin_back(_id, _rank, _pinned), do: :ok

  defp package_back(_id, same, same), do: :ok
  defp package_back(id, _now, nil), do: unfile(id)
  defp package_back(id, _now, ref), do: file(id, ref)

  @doc "p: pin a ranked card at its rank, or unpin a pinned one."
  @spec toggle_pin(map()) :: {:ok, :pinned | :unpinned} | {:error, atom()}
  def toggle_pin(%{pinned: 1, card_id: id}), do: with(:ok <- unpin(id), do: {:ok, :unpinned})
  def toggle_pin(%{rank: nil}), do: {:error, :unranked_pin}

  def toggle_pin(%{card_id: id, rank: rank}),
    do: with(:ok <- rank_at(id, rank), do: {:ok, :pinned})

  def file(card_id, package_ref),
    do: run(FileCardV1, MaybeFileCard, %{card_id: card_id, package_ref: package_ref})

  def unfile(card_id), do: run(UnfileCardV1, MaybeUnfileCard, %{card_id: card_id})

  def reserve(card_id, lane),
    do: run(ReserveCardV1, MaybeReserveCard, %{card_id: card_id, lane: lane})

  def lift(card_id), do: run(LiftCardReservationV1, MaybeLiftCardReservation, %{card_id: card_id})

  def withdraw(card_id, reason),
    do: run(WithdrawCardV1, MaybeWithdrawCard, %{card_id: card_id, reason: reason})

  def release(card_id, reason),
    do: run(ReleaseCardV1, MaybeReleaseCard, %{card_id: card_id, reason: reason})

  def block(card_id, reason),
    do: run(BlockCardV1, MaybeBlockCard, %{card_id: card_id, reason: reason})

  def unblock(card_id), do: run(UnblockCardV1, MaybeUnblockCard, %{card_id: card_id})

  def reclassify(card_id, kind),
    do: run(ReclassifyCardV1, MaybeReclassifyCard, %{card_id: card_id, kind: kind})

  def comment(card_id, text),
    do: run(CommentOnCardV1, MaybeCommentOnCard, %{card_id: card_id, text: text})

  def tag(card_id, tag), do: run(TagCardV1, MaybeTagCard, %{card_id: card_id, tag: tag})
  def untag(card_id, tag), do: run(UntagCardV1, MaybeUntagCard, %{card_id: card_id, tag: tag})

  def reword(card_id, p),
    do:
      run(RewordCardV1, MaybeRewordCard, %{card_id: card_id, title: p["title"], story: story(p)})

  defp run(command, desk, args) do
    with {:ok, cmd} <- command.new(Map.put(args, :by, Actor.owner())),
         {:ok, _version, _events} <- desk.dispatch(cmd),
         do: :ok
  end

  defp story(p) do
    parts = %{role: blank(p["role"]), ask: blank(p["ask"]), value: blank(p["value"])}
    if Enum.all?(Map.values(parts), &is_nil/1), do: nil, else: parts
  end

  defp blank(nil), do: nil
  defp blank(text), do: if(String.trim(text) == "", do: nil, else: text)

  defp tags(nil), do: []

  defp tags(text),
    do: text |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  @doc """
  A refusal in words an owner can act on: what happened and how to fix it.
  Every reason a desk returns has its own words; an unknown one still names
  itself.
  """
  @spec explain(atom()) :: %{reason: String.t(), text: String.t(), fix: String.t()}
  def explain(reason) do
    {text, fix} =
      Map.get(@refusals, reason, {"The board refused this", "Reload the page and try again."})

    %{reason: Atom.to_string(reason), text: text, fix: fix}
  end
end
