defmodule MclKanban.Wire do
  # How the board crosses the mesh. In: arguments as a plain mesh_call sends
  # them (text keys, text values as {:text, _}), read with mcl_om_wire. Out:
  # replies with text as CBOR text, numbers as numbers, no booleans and no
  # nulls (an absent value is an absent key). A refusal is a normal reply
  # naming its reason, %{reason: "already_claimed"}, the same shape as
  # claim_next_card's board_empty, so an agent reads it as plain text.
  @moduledoc false

  require Logger

  alias QueryBoards.GetCardById.GetCardById

  @card_fields ~w(card_id issue_ref board title story kind colour tags rank rationale lane holder
                  status state pinned note links linked_from comment_count queued_at claimed_at comments
                  work_package package_rank package_card)a

  @doc "An argument, unwrapped."
  def arg(payload, key), do: :mcl_om_wire.field(key, payload, nil)

  @doc "The optional story argument: a map of role, ask and value."
  def story(payload) do
    case arg(payload, :story) do
      story when is_map(story) -> Map.new(story, fn {k, v} -> {story_key(k), v} end)
      other -> other
    end
  end

  defp story_key({:text, k}), do: story_key(k)
  defp story_key(k) when k in ["role", "ask", "value"], do: String.to_existing_atom(k)
  defp story_key(k), do: k

  @doc "After a card command: the card as its own event left it."
  def card_after(card_id, version) do
    case GetCardById.get_card_by_id(card_id, version) do
      {:ok, card} -> {:ok, %{card: card(card)}}
      {:error, _} = error -> error
    end
  end

  @doc """
  After a command whose reply is not the card (queue_card's card_id,
  comment_on_card's comment_id): the reply, once the read model holds the
  card at the command's version, so the caller's next read sees its own write.
  """
  def once_read(card_id, version, reply) do
    case GetCardById.get_card_by_id(card_id, version) do
      {:ok, _card} -> {:ok, reply}
      {:error, _} = error -> error
    end
  end

  @doc "A card as the wire carries it."
  def card(card), do: Map.take(card, @card_fields)

  @doc "The reply for a result, ready for macula."
  def reply({:ok, map}) when is_map(map), do: out(map)
  def reply({:error, reason}) when is_atom(reason), do: %{reason: {:text, Atom.to_string(reason)}}

  def reply(other) do
    Logger.error("mcl-kanban: unexpected outcome #{inspect(other)}")
    %{reason: {:text, "internal_error"}}
  end

  defp out(map) when is_map(map),
    do: for({k, v} <- map, v != nil, into: %{}, do: {k, out(v)})

  defp out(list) when is_list(list), do: Enum.map(list, &out/1)
  defp out(text) when is_binary(text), do: {:text, text}
  defp out(value), do: value
end
