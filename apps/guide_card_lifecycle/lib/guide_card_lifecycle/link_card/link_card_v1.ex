defmodule GuideCardLifecycle.LinkCard.LinkCardV1 do
  # Command: link a card to another card, on the same board or another: it blocks, relates to or follows up that card. The link is stored on this (the source) card.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, IssueRef}

  @links ["blocks", "relates_to", "follows_up"]

  @enforce_keys [:card_id, :to_card_id, :link, :by]
  defstruct [:card_id, :to_card_id, :link, :by]

  @impl true
  def command_type, do: :link_card

  @doc "The kinds of link: blocks, relates_to, follows_up."
  def links, do: @links

  @impl true
  def new(%{card_id: id, to_card_id: to, link: link, by: %Actor{} = by}) do
    with {:ok, id} <- IssueRef.valid_card_id(id),
         {:ok, to} <- IssueRef.valid_card_id(to),
         {:ok, link} <- link(link),
         :ok <- other(id, to),
         do: {:ok, %__MODULE__{card_id: id, to_card_id: to, link: link, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  defp link(link) when link in @links, do: {:ok, link}
  defp link(_), do: {:error, :invalid_link}

  defp other(id, id), do: {:error, :self_link}
  defp other(_id, _to), do: :ok

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
