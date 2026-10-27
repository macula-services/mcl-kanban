defmodule GuideCardLifecycle.ObserveCrewFact.ObserveCrewFactV1 do
  # Command: the board accepted the realm's crew fact at `seq` (#40). It is
  # how "the highest seq per crew_id wins" survives a restart: the seq lives
  # in the crew's own event stream, not in a process's memory.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.Actor

  @enforce_keys [:crew_id, :crew_name, :fact, :seq, :by]
  defstruct [:crew_id, :crew_name, :fact, :seq, :by]

  @impl true
  def command_type, do: :observe_crew_fact

  @impl true
  def new(%{crew_id: crew_id, crew_name: crew_name, fact: fact, seq: seq, by: %Actor{} = by})
      when is_binary(crew_id) and is_binary(crew_name) and is_binary(fact) and is_integer(seq) do
    {:ok, %__MODULE__{crew_id: crew_id, crew_name: crew_name, fact: fact, seq: seq, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
