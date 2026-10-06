defmodule ProjectBoards.Projection do
  # What every {event}_to_{table} projection does around its own statements:
  # take the event out of evoq's envelope with its stream version, write the
  # statements in one transaction, and announce the write.
  #
  # Card rows only move forward: each card statement is guarded on the row's
  # version, so a redelivered or late event never undoes a newer one.
  @moduledoc false

  alias ProjectBoards.BoardsChanged
  alias ProjectBoards.ReadModel

  @spec project(String.t(), map(), (map(), integer() -> [{String.t(), list()}])) ::
          {:ok, map()} | {:error, term()}
  def project(event_type, envelope, statements) do
    data = Map.get(envelope, :data, envelope)
    version = Map.get(envelope, :version, 0)
    written(ReadModel.write(statements.(data, version)), event_type, data)
  end

  defp written(:ok, event_type, data) do
    BoardsChanged.broadcast(event_type, data)
    {:ok, %{}}
  end

  defp written({:error, reason}, _event_type, _data), do: {:error, {:read_model, reason}}

  @doc "The guarded update of a card row: the fields, its status, its version."
  def card_update(data, version, fields) do
    {sets, args} = Enum.unzip(fields)
    set = Enum.map_join(sets ++ ["status", "changed_at", "version"], ", ", &(&1 <> " = ?"))

    {"UPDATE cards SET #{set} WHERE card_id = ? AND version < ?",
     args ++ [data.status, data.at, version, data.card_id, version]}
  end

  @doc "A statement that runs only while the card row is older than this event."
  def guarded(sql, args, data, version),
    do:
      {sql <> " WHERE (SELECT version FROM cards WHERE card_id = ?) < ?",
       args ++ [data.card_id, version]}
end
