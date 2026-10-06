defmodule QueryBoards.GetCardById.GetCardById do
  # get_card_by_id: one card with its comment thread.
  #
  # get_card_by_id/3 waits (bounded) until the read model holds the card at
  # least at a given stream version: a command's reply reads the card its own
  # event produced, never the row from before it.
  @moduledoc false

  alias QueryBoards.CardRows
  alias QueryBoards.ReadModel

  @spec get_card_by_id(String.t()) :: {:ok, map()} | {:error, :unknown_card}
  def get_card_by_id(card_id) when is_binary(card_id) do
    case CardRows.cards("WHERE c.card_id = ?", [card_id]) do
      [card] -> {:ok, Map.put(card, :comments, CardRows.comments(card_id))}
      [] -> {:error, :unknown_card}
    end
  end

  def get_card_by_id(_), do: {:error, :unknown_card}

  @spec get_card_by_id(String.t(), non_neg_integer(), pos_integer()) ::
          {:ok, map()} | {:error, :read_model_behind}
  def get_card_by_id(card_id, version, timeout_ms \\ 5_000),
    do: await(card_id, version, System.monotonic_time(:millisecond) + timeout_ms)

  # Each poll reads the card's version alone; the whole card (tags, links,
  # comments) is read once, when the version has arrived.
  defp await(card_id, version, deadline) do
    case ReadModel.q("SELECT version FROM cards WHERE card_id = ?", [card_id]) do
      [[v]] when v >= version ->
        get_card_by_id(card_id)

      _behind ->
        retry(card_id, version, deadline, System.monotonic_time(:millisecond) >= deadline)
    end
  end

  defp retry(_card_id, _version, _deadline, true), do: {:error, :read_model_behind}

  defp retry(card_id, version, deadline, false) do
    Process.sleep(15)
    await(card_id, version, deadline)
  end
end
