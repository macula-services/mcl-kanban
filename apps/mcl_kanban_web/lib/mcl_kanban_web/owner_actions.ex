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
  alias GuideCardLifecycle.UnpinCard.{MaybeUnpinCard, UnpinCardV1}
  alias GuideCardLifecycle.UntagCard.{MaybeUntagCard, UntagCardV1}
  alias GuideCardLifecycle.WithdrawCard.{MaybeWithdrawCard, WithdrawCardV1}

  @type outcome :: :ok | {:error, atom()}

  @spec enlist(map()) :: outcome()
  def enlist(p),
    do: run(EnlistAgentV1, MaybeEnlistAgent, %{name: p["name"], node_id: p["node_id"]})

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

  @doc "A refusal in words an owner can act on."
  @spec explain(atom()) :: String.t()
  def explain(reason) do
    hint =
      Map.get(
        %{
          invalid_repo: "a repo reads owner/repo",
          invalid_issue_ref: "an issue reads owner/repo#number",
          unknown_board: "open the repo's board first",
          board_archived: "that board is archived",
          already_on_board: "that issue already has a card",
          invalid_node_id: "a node id is 64 hex characters",
          invalid_name: "a name starts with a letter: letters, digits, - and _",
          name_reserved: "owner is reserved",
          name_taken: "another agent has that name",
          already_enlisted: "that node id is already enlisted",
          unknown_agent: "enlist the agent first",
          supervisor_required: "appoint another supervisor first",
          invalid_rank: "a rank is a whole number, 0 or more; lower is claimed first",
          invalid_story: "a story needs all three parts, or none"
        },
        reason
      )

    if hint, do: "#{reason}: #{hint}", else: Atom.to_string(reason)
  end
end
