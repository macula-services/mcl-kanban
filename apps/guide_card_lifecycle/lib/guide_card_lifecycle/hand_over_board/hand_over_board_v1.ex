defmodule GuideCardLifecycle.HandOverBoard.HandOverBoardV1 do
  # Command: hand a repo's board, owner/repo, over to another crew (#29). The
  # board id is derived from the repo.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CrewName
  alias GuideCardLifecycle.IssueRef

  @enforce_keys [:board_id, :repo, :crew, :by]
  defstruct [:board_id, :repo, :crew, :by]

  @impl true
  def command_type, do: :hand_over_board

  @impl true
  def new(%{repo: repo, crew: crew, by: %Actor{} = by}) do
    with {:ok, repo} <- IssueRef.repo(repo),
         {:ok, crew} <- CrewName.name(crew),
         do: {:ok, %__MODULE__{board_id: IssueRef.board_id(repo), repo: repo, crew: crew, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
