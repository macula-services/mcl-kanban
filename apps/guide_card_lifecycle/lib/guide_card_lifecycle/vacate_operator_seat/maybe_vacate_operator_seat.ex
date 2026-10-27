defmodule GuideCardLifecycle.VacateOperatorSeat.MaybeVacateOperatorSeat do
  # Handler: the realm empties the operator seat of a crew it dropped (#40).
  # Nobody else: the owner empties a seat by appointing another operator, and
  # an operator hands its own crew on the same way. A crew with no one in the
  # seat has nothing to vacate, and that is a refusal rather than a quiet
  # success, so a caller learns its fact named a crew the board holds no
  # operator for.
  @moduledoc false

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewState
  alias GuideCardLifecycle.VacateOperatorSeat.{OperatorSeatVacatedV1, VacateOperatorSeatV1}

  @who [:realm]

  def handle_payload(state, payload), do: handle(state, struct(VacateOperatorSeatV1, payload))

  def handle(%CrewState{} = crew, %VacateOperatorSeatV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      CrewState.operator_of(crew, cmd.crew) == nil -> {:error, :no_operator}
      true -> {:ok, [OperatorSeatVacatedV1.new(cmd.by, cmd.crew)]}
    end
  end

  def dispatch(%VacateOperatorSeatV1{} = cmd) do
    :evoq_command.new(
      :vacate_operator_seat,
      CrewAggregate,
      CrewAggregate.stream_id(),
      VacateOperatorSeatV1.to_map(cmd)
    )
    |> :evoq_router.dispatch()
  end
end
