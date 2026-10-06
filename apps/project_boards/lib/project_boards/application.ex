defmodule ProjectBoards.Application do
  # The PRJ department: the pubsub seam first (so a projection can announce
  # the moment it starts; the web app depends on this app, so the registry
  # exists before any LiveView), then the read model's Repo (already migrated
  # by bin/start, or by the test alias), then one
  # evoq_event_handler per projection. The service app opens the store AFTER
  # this app has started, so every projection is registered when the store
  # subscription begins delivering.
  @moduledoc false

  use Application

  @projections [
    ProjectBoards.AgentDischargedV1ToCrew,
    ProjectBoards.AgentEnlistedV1ToCrew,
    ProjectBoards.BoardArchivedV1ToBoards,
    ProjectBoards.BoardOpenedV1ToBoards,
    ProjectBoards.CardBlockedV1ToCards,
    ProjectBoards.CardClaimedV1ToCards,
    ProjectBoards.CardCommentedV1ToCardComments,
    ProjectBoards.CardFiledV1ToCards,
    ProjectBoards.CardFinishedV1ToCards,
    ProjectBoards.CardLinkedV1ToCardLinks,
    ProjectBoards.CardPrioritisedV1ToCards,
    ProjectBoards.CardQueuedV1ToCards,
    ProjectBoards.CardReclassifiedV1ToCards,
    ProjectBoards.CardReleasedV1ToCards,
    ProjectBoards.CardReservationLiftedV1ToCards,
    ProjectBoards.CardReservedV1ToCards,
    ProjectBoards.CardRewordedV1ToCards,
    ProjectBoards.CardTaggedV1ToCardTags,
    ProjectBoards.CardUnblockedV1ToCards,
    ProjectBoards.CardUnfiledV1ToCards,
    ProjectBoards.CardUnlinkedV1ToCardLinks,
    ProjectBoards.CardUnpinnedV1ToCards,
    ProjectBoards.CardUntaggedV1ToCardTags,
    ProjectBoards.CardWithdrawnV1ToCards,
    ProjectBoards.PackageOpenedV1ToPackages,
    ProjectBoards.PackagePrioritisedV1ToPackages,
    ProjectBoards.PackageUnpinnedV1ToPackages,
    ProjectBoards.PrioritiserAppointedV1ToCrew,
    ProjectBoards.SupervisorAppointedV1ToCrew
  ]

  @doc "Every projection this department runs."
  def projections, do: @projections

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: MclKanbanWeb.PubSub},
        ProjectBoards.Repo
      ] ++ Enum.map(@projections, &handler/1)

    Supervisor.start_link(children, strategy: :one_for_one, name: ProjectBoards.Supervisor)
  end

  defp handler(module) do
    %{
      id: module,
      start: {:evoq_event_handler, :start_link, [module, %{}]},
      restart: :permanent,
      type: :worker
    }
  end
end
