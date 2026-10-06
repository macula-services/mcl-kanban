defmodule GuideCardLifecycle.LiftCardReservation.MaybeLiftCardReservation do
  # Handler: the supervisor, the prioritiser or the owner lifts a lane.
  @moduledoc false

  alias GuideCardLifecycle.{Actor, CardAggregate, CardState}
  alias GuideCardLifecycle.LiftCardReservation.{CardReservationLiftedV1, LiftCardReservationV1}

  @who [:supervisor, :prioritiser, :owner]

  def handle_payload(state, payload), do: handle(state, struct(LiftCardReservationV1, payload))

  def handle(%CardState{} = card, %LiftCardReservationV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      card.lane == nil -> {:error, :not_reserved}
      true -> {:ok, [CardReservationLiftedV1.new(cmd, card.status, %{lane: card.lane})]}
    end
  end

  def dispatch(%LiftCardReservationV1{} = cmd),
    do:
      CardAggregate.dispatch(
        :lift_card_reservation,
        cmd.card_id,
        LiftCardReservationV1.to_map(cmd)
      )
end
