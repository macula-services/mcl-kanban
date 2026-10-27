defmodule GuideCardLifecycle.VacateOperatorSeat.VacateOperatorSeatV1 do
  # Command: empty a crew's operator seat (#40). The realm drops a crew, and
  # the agent in that seat is one the board's own rules refuse to discharge --
  # the supervisor, or a prioritiser the owner appointed -- so the seat would
  # otherwise stand, and that agent could keep enlisting into a crew the realm
  # has revoked, left or suspended.
  #
  # It acts as the realm, and only as the realm: it is the realm's own drop of
  # the crew that takes the seat, never a caller's. `crew` is a crew KEY.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CrewName

  @enforce_keys [:crew, :by]
  defstruct [:crew, :by]

  @impl true
  def command_type, do: :vacate_operator_seat

  @impl true
  def new(%{crew: crew, by: %Actor{} = by}) do
    with {:ok, crew} <- CrewName.key(crew), do: {:ok, %__MODULE__{crew: crew, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
