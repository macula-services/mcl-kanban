defmodule GuideCardLifecycle.DeferBoard.DeferBoardV1 do
  # Command: pause a repo's board, with a reason: its cards are not handed out. The board id is derived from the repo.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, CardText, IssueRef}

  @enforce_keys [:board_id, :repo, :by]
  defstruct [:board_id, :repo, :reason, :by]

  @impl true
  def command_type, do: :defer_board

  @impl true
  def new(%{repo: repo, reason: text, by: %Actor{} = by}) do
    with {:ok, repo} <- IssueRef.repo(repo),
         {:ok, text} <- CardText.required(text, 500, :reason_required),
         do:
           {:ok, %__MODULE__{board_id: IssueRef.board_id(repo), repo: repo, reason: text, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
