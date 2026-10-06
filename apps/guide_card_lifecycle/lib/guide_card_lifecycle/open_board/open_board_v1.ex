defmodule GuideCardLifecycle.OpenBoard.OpenBoardV1 do
  # Command: open_board for a repo, owner/repo. The board id is derived from it.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.IssueRef

  @enforce_keys [:board_id, :repo, :by]
  defstruct [:board_id, :repo, :by]

  @impl true
  def command_type, do: :open_board

  @impl true
  def new(%{repo: repo, by: %Actor{} = by}) do
    with {:ok, repo} <- IssueRef.repo(repo),
         do: {:ok, %__MODULE__{board_id: IssueRef.board_id(repo), repo: repo, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
