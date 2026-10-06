defmodule GuideCardLifecycle.RewordCard.RewordCardV1 do
  # Command: a new title, and optionally a new story.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, CardStory, CardText, IssueRef}

  @enforce_keys [:card_id, :title, :by]
  defstruct [:card_id, :title, :story, :by]

  @impl true
  def command_type, do: :reword_card

  @impl true
  def new(%{card_id: id, title: title, by: %Actor{} = by} = params) do
    with {:ok, id} <- IssueRef.valid_card_id(id),
         {:ok, title} <- CardText.required(title, 200, :title_required),
         {:ok, story} <- CardStory.story(Map.get(params, :story)),
         do: {:ok, %__MODULE__{card_id: id, title: title, story: story, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
