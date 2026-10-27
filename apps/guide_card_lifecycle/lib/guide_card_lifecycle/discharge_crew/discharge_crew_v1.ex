defmodule GuideCardLifecycle.DischargeCrew.DischargeCrewV1 do
  # Command: the board discharges a crew the realm has stopped knowing (#40).
  # Its agents lose the board and its seq is kept, so a replay of an old fact
  # cannot put them back. The reason is the board's own: today only
  # "unknown_crew_after_n", the realm answering unknown_crew for the crew on
  # n consecutive reconciles.
  #
  # This is the board's act, not the realm's: it is decided by the reconcile
  # from an UNSIGNED answer, so it acts as `Actor.board()` -- an actor no
  # payload can build and no signature can produce.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CrewName

  @enforce_keys [:crew, :reason, :by]
  defstruct [:crew, :reason, :by]

  @impl true
  def command_type, do: :discharge_crew

  @impl true
  def new(%{crew: crew, reason: reason, by: %Actor{} = by}) do
    with {:ok, crew} <- CrewName.key(crew) do
      {:ok, %__MODULE__{crew: crew, reason: reason, by: by}}
    end
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
