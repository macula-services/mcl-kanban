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

  @doc "The guarded update of a package row: the fields, its pin, its version."
  def package_update(data, version, fields) do
    {sets, args} = Enum.unzip(fields ++ [{"pinned", pinned(data.status)}])
    set = Enum.map_join(sets ++ ["version"], ", ", &(&1 <> " = ?"))

    {"UPDATE packages SET #{set} WHERE package_id = ? AND version < ?",
     args ++ [version, data.package_id, version]}
  end

  defp pinned(status),
    do: flag(:evoq_bit_flags.has(status, GuideCardLifecycle.PackageStatus.pinned()))

  defp flag(true), do: 1
  defp flag(false), do: 0

  @doc """
  Recomputes cards.deferred for the cards the condition picks (#17): 1 while
  the card's own DEFERRED bit is set, its package is paused or its board is.
  Every projection that can change one of the three runs it.
  """
  def deferred(condition, args),
    do:
      {"UPDATE cards SET deferred = (status & 64 = 64 " <>
         "OR EXISTS (SELECT 1 FROM packages p WHERE p.issue_ref = cards.work_package AND p.deferred = 1) " <>
         "OR EXISTS (SELECT 1 FROM boards b WHERE b.board_id = cards.board_id AND b.status & 4 = 4)) " <>
         "WHERE " <> condition, args}

  @doc "A statement that runs only while the card row is older than this event."
  def guarded(sql, args, data, version),
    do:
      {sql <> " WHERE (SELECT version FROM cards WHERE card_id = ?) < ?",
       args ++ [data.card_id, version]}
end
