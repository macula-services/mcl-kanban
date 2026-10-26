defmodule GuideCardLifecycle.LiftCardReservation.MaybeLiftCardReservation do
  # Handler: the home crew's supervisor, prioritiser or operator, or the
  # owner (#29), lifts a lane, an agent's or a crew's.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState, CrewName}
  alias GuideCardLifecycle.LiftCardReservation.{CardReservationLiftedV1, LiftCardReservationV1}

  @who [:supervisor, :prioritiser, :owner]

  def handle_payload(state, payload), do: handle(state, struct(LiftCardReservationV1, payload))

  def handle(%CardState{} = card, %LiftCardReservationV1{} = cmd) do
    cond do
      refusal = Actor.refused(cmd.by, @who, CrewName.home_crew_in(card)) ->
        {:error, refusal}

      card.lane == nil and card.lane_crew == nil ->
        {:error, :not_reserved}

      true ->
        {:ok, [CardReservationLiftedV1.new(cmd, card.status, lifted(card))]}
    end
  end

  defp lifted(card), do: %{lane: card.lane, lane_crew: card.lane_crew}

  def dispatch(%LiftCardReservationV1{} = cmd),
    do:
      CardAggregate.dispatch(
        :lift_card_reservation,
        cmd.card_id,
        LiftCardReservationV1.to_map(cmd)
      )
end
