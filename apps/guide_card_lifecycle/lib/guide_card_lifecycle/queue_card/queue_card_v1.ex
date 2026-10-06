defmodule GuideCardLifecycle.QueueCard.QueueCardV1 do
  # Command: put a GitHub issue on its repo's board as a card. The card and
  # board ids are derived from the issue reference.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CardKind
  alias GuideCardLifecycle.CardStory
  alias GuideCardLifecycle.CardTag
  alias GuideCardLifecycle.CardText
  alias GuideCardLifecycle.IssueRef

  @enforce_keys [:card_id, :board_id, :issue_ref, :repo, :title, :kind, :by]
  defstruct [:card_id, :board_id, :issue_ref, :repo, :title, :story, :kind, :by, tags: []]

  @impl true
  def command_type, do: :queue_card

  @impl true
  def new(%{issue_ref: ref, title: title, kind: kind, by: %Actor{} = by} = params) do
    with {:ok, %{repo: repo}} <- IssueRef.parse(ref),
         {:ok, title} <- CardText.required(title, 200, :title_required),
         {:ok, kind} <- CardKind.kind(kind),
         {:ok, story} <- CardStory.story(Map.get(params, :story)),
         {:ok, tags} <- CardTag.tags(Map.get(params, :tags)) do
      {:ok,
       %__MODULE__{
         card_id: IssueRef.card_id(ref),
         board_id: IssueRef.board_id(repo),
         issue_ref: ref,
         repo: repo,
         title: title,
         story: story,
         kind: kind,
         tags: tags,
         by: by
       }}
    end
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
