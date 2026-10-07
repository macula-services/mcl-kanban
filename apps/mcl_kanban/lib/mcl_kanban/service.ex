defmodule MclKanban.Service do
  # The mcl_om service contract for mcl-kanban: the board the crew pulls its
  # next card from, on our own mesh (macula-services/mcl-kanban#2).
  #
  # Every procedure is mcl-kanban/<name> in the io.macula realm, and every one
  # acts as its CALLER: the node id that signed the call, looked up in the
  # crew (GuideCardLifecycle.Actor). auth is :open at the mesh because the
  # role gate is the board's own; a caller the crew does not know gets
  # reason not_enlisted from every procedure.
  #
  # SEALED (#4, #21): every procedure is confidential: :required. The
  # advertisement names this node's KEM key (macula's kem_advertise is
  # enabled in config/runtime.exs), each call is sealed end to end, and a
  # call in the clear is refused before a responder sees it. Reads too: a
  # reply carries card titles, notes and agent names.
  #
  # The store is this service's own: event_store/0 describes it and
  # MclKanban.Application opens it before mcl_om:boot/1. NOT store_id/0 and
  # data_dir/0, which mcl_om stopped honouring at 0.35.
  @moduledoc false

  @behaviour :mcl_om_service

  alias MclKanban.{
    AdoptGoal,
    ArchiveBoard,
    BlockCard,
    ClaimCard,
    ClaimNextCard,
    CommentOnCard,
    DeferBoard,
    DeferCard,
    DeferPackage,
    DischargeAgent,
    EnlistAgent,
    FileCard,
    FinishCard,
    GetBoardByRepo,
    GetBoards,
    GetCardById,
    GetGoal,
    GetLadder,
    GetMyCards,
    LiftCardReservation,
    LinkCard,
    OpenBoard,
    OpenPackage,
    PrioritiseCard,
    PrioritisePackage,
    QueueCard,
    ReclassifyCard,
    ReleaseCard,
    ReserveCard,
    ResumeBoard,
    ResumeCard,
    ResumePackage,
    RewordCard,
    TagCard,
    UnblockCard,
    UnfileCard,
    UnlinkCard,
    UntagCard,
    WithdrawCard
  }

  @store_probe_ms 1_000

  @procedures [
    {"claim_next_card", ClaimNextCard.ClaimNextCardResponder},
    {"claim_card", ClaimCard.ClaimCardResponder},
    {"unblock_card", UnblockCard.UnblockCardResponder},
    {"release_card", ReleaseCard.ReleaseCardResponder},
    {"block_card", BlockCard.BlockCardResponder},
    {"finish_card", FinishCard.FinishCardResponder},
    {"queue_card", QueueCard.QueueCardResponder},
    {"reword_card", RewordCard.RewordCardResponder},
    {"reclassify_card", ReclassifyCard.ReclassifyCardResponder},
    {"tag_card", TagCard.TagCardResponder},
    {"untag_card", UntagCard.UntagCardResponder},
    {"link_card", LinkCard.LinkCardResponder},
    {"unlink_card", UnlinkCard.UnlinkCardResponder},
    {"comment_on_card", CommentOnCard.CommentOnCardResponder},
    {"prioritise_card", PrioritiseCard.PrioritiseCardResponder},
    {"reserve_card", ReserveCard.ReserveCardResponder},
    {"lift_card_reservation", LiftCardReservation.LiftCardReservationResponder},
    {"withdraw_card", WithdrawCard.WithdrawCardResponder},
    {"get_boards", GetBoards.GetBoardsResponder},
    {"get_board_by_repo", GetBoardByRepo.GetBoardByRepoResponder},
    {"get_card_by_id", GetCardById.GetCardByIdResponder},
    {"get_my_cards", GetMyCards.GetMyCardsResponder},
    {"enlist_agent", EnlistAgent.EnlistAgentResponder},
    {"discharge_agent", DischargeAgent.DischargeAgentResponder},
    {"open_board", OpenBoard.OpenBoardResponder},
    {"archive_board", ArchiveBoard.ArchiveBoardResponder},
    {"open_package", OpenPackage.OpenPackageResponder},
    {"prioritise_package", PrioritisePackage.PrioritisePackageResponder},
    {"file_card", FileCard.FileCardResponder},
    {"unfile_card", UnfileCard.UnfileCardResponder},
    {"get_ladder", GetLadder.GetLadderResponder},
    {"defer_card", DeferCard.DeferCardResponder},
    {"resume_card", ResumeCard.ResumeCardResponder},
    {"defer_package", DeferPackage.DeferPackageResponder},
    {"resume_package", ResumePackage.ResumePackageResponder},
    {"defer_board", DeferBoard.DeferBoardResponder},
    {"resume_board", ResumeBoard.ResumeBoardResponder},
    {"adopt_goal", AdoptGoal.AdoptGoalResponder},
    {"get_goal", GetGoal.GetGoalResponder}
  ]

  @impl true
  def info do
    %{
      name: "mcl-kanban",
      version: version(),
      description:
        "Kanban boards for the crew: one board per repo, cards claimed in rank order over the mesh"
    }
  end

  @impl true
  def start(_opts), do: MclKanban.Supervisor.start_link()

  @impl true
  def stop(_state), do: :ok

  # The board works when both halves answer: the read model serves every
  # query, the event store takes every write. A dead store behind a live read
  # model once reported ok for over an hour (#11).
  @impl true
  def health, do: health(event_store().id)

  @doc false
  def health(store_id), do: verdict(Map.merge(read_model_problem(), store_problem(store_id)))

  defp verdict(problems) when map_size(problems) == 0, do: :ok
  defp verdict(problems), do: {:degraded, problems}

  defp read_model_problem do
    case ProjectBoards.Repo.query("SELECT 1", [], timeout: 1_000) do
      {:ok, _} -> %{}
      {:error, reason} -> %{read_model: inspect(reason)}
    end
  catch
    :exit, _ -> %{read_model: :missing}
  end

  # reckon_db_store:is_ready/1 reads the store's root through khepri: false
  # once the store or its Ra server is gone. Bounded, so a store stuck on its
  # disk cannot hang the health check. khepri's own error tuple can come
  # through is_ready unchanged.
  defp store_problem(store_id) do
    task = Task.async(fn -> :reckon_db_store.is_ready(store_id) end)

    case Task.yield(task, @store_probe_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, true} -> %{}
      {:ok, false} -> %{event_store: :not_ready}
      {:ok, other} -> %{event_store: inspect(other)}
      nil -> %{event_store: :timeout}
    end
  end

  @impl true
  def capabilities do
    for {name, responder} <- @procedures,
        do: %{
          name: name,
          version: 1,
          handler: {responder, []},
          auth: :open,
          confidential: :required
        }
  end

  # The namespace every procedure hangs under. The procedures are calls,
  # each served under its own provider grant, and the board publishes no
  # topics in part 1, so it asks for nothing more.
  @impl true
  def identity_spec, do: %{scope: "mcl-kanban", actions: [], resources: [], ttl_days: 30}

  @doc """
  The reckon-db store this service owns. The id is named twice, here and in
  the evoq block of config/runtime.exs; a test compares them. The directory
  is MCL_DATA_DIR, a mounted volume on a box (a bulk drive on the fleet).
  """
  def event_store do
    %{
      id: :mcl_kanban_store,
      dir: String.to_charlist(System.get_env("MCL_DATA_DIR", "/tmp/mcl-kanban-dev")),
      indexes: [],
      mode: :single,
      integrity: :disabled
    }
  end

  defp version do
    {:ok, vsn} = :application.get_key(:mcl_kanban, :vsn)
    to_string(vsn)
  end
end
