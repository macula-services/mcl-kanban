defmodule GuideCardLifecycle.AppointOperator.MaybeAppointOperator do
  # Handler: only the owner appoints an operator, and only an agent enlisted in
  # that very crew. Appointing the one already sitting is refused. The owner
  # keeps this one because an operator appoints its own successor: that would
  # let a crew hand itself on without anyone outside it agreeing (#28).
  #
  # The realm appoints too, since it is the outside agreement: it admitted the
  # crew and named its operator (#40). That actor is only ever constructed by
  # the consumer that verified the realm's signature, never from a caller.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AppointOperator.{AppointOperatorV1, OperatorAppointedV1}
  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewState

  @who [:owner, :realm]

  def handle_payload(state, payload), do: handle(state, struct(AppointOperatorV1, payload))

  # The crew the appointment names is a KEY (#40 option b), as enlisting's is:
  # a bare name for a crew the board's owner made, a 64-hex `crew_id` for one
  # the realm admitted, never resolved from a name.
  def handle(%CrewState{} = crew, %AppointOperatorV1{} = cmd), do: seat(crew, cmd)

  defp seat(crew, cmd) do
    node_id = CrewState.node_id_of(crew, cmd.name)

    cond do
      not Actor.allowed?(cmd.by, @who) ->
        {:error, :not_permitted}

      node_id == nil ->
        {:error, :unknown_agent}

      CrewState.crew_of(crew, node_id) != cmd.crew ->
        {:error, :agent_in_another_crew}

      CrewState.operator_of(crew, cmd.crew) == node_id ->
        {:error, :already_appointed}

      true ->
        {:ok,
         [OperatorAppointedV1.new(cmd.by, cmd.crew, node_id, CrewState.name_of(crew, node_id))]}
    end
  end

  def dispatch(%AppointOperatorV1{} = cmd) do
    :evoq_command.new(
      :appoint_operator,
      CrewAggregate,
      CrewAggregate.stream_id(),
      AppointOperatorV1.to_map(cmd)
    )
    |> :evoq_router.dispatch()
  end
end
