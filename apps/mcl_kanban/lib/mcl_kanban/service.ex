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
  # FIRST ITERATION: no procedure sets confidential: :required (Raf's
  # decision on #2, 2026-10-06). Calls travel as macula's default allows;
  # sealing comes in a later iteration.
  #
  # The store is this service's own: event_store/0 describes it and
  # MclKanban.Application opens it before mcl_om:boot/1. NOT store_id/0 and
  # data_dir/0, which mcl_om stopped honouring at 0.35.
  @moduledoc false

  @behaviour :mcl_om_service

  alias MclKanban.{
    ArchiveBoard,
    BlockCard,
    ClaimCard,
    ClaimNextCard,
    CommentOnCard,
    DischargeAgent,
    EnlistAgent,
    FileCard,
    FinishCard,
    GetBoardByRepo,
    GetBoards,
    GetCardById,
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
    RewordCard,
    TagCard,
    UnblockCard,
    UnfileCard,
    UnlinkCard,
    UntagCard,
    WithdrawCard
  }

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
    {"get_ladder", GetLadder.GetLadderResponder}
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

  # The board is reachable when both read model connections answer.
  @impl true
  def health do
    case {ping(ProjectBoards.ReadModel), ping(QueryBoards.ReadModel)} do
      {:ok, :ok} -> :ok
      {projections, queries} -> {:degraded, %{read_model: projections, queries: queries}}
    end
  end

  defp ping(name) do
    GenServer.call(name, :ping, 1_000)
  catch
    :exit, _ -> :missing
  end

  @impl true
  def capabilities do
    for {name, responder} <- @procedures,
        do: %{name: name, version: 1, handler: {responder, []}, auth: :open}
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
