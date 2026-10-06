defmodule GuideCardLifecycle.AppointPrioritiser.MaybeAppointPrioritiser do
  # Handler: only the owner appoints, and only an enlisted agent. Appointing
  # the one already sitting is refused.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AppointPrioritiser.{PrioritiserAppointedV1, AppointPrioritiserV1}
  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewState

  @who [:owner]

  def handle_payload(state, payload), do: handle(state, struct(AppointPrioritiserV1, payload))

  def handle(%CrewState{} = crew, %AppointPrioritiserV1{} = cmd) do
    node_id = CrewState.node_id_of(crew, cmd.name)

    cond do
      not Actor.allowed?(cmd.by, @who) ->
        {:error, :not_permitted}

      node_id == nil ->
        {:error, :unknown_agent}

      node_id == crew.prioritiser ->
        {:error, :already_appointed}

      true ->
        {:ok, [PrioritiserAppointedV1.new(cmd.by, node_id, CrewState.name_of(crew, node_id))]}
    end
  end

  def dispatch(%AppointPrioritiserV1{} = cmd) do
    :evoq_command.new(
      :appoint_prioritiser,
      CrewAggregate,
      CrewAggregate.stream_id(),
      AppointPrioritiserV1.to_map(cmd)
    )
    |> :evoq_router.dispatch()
  end
end
