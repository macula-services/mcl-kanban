defmodule GuideCardLifecycle.OpenBoard.OpenBoardV1 do
  # Command: open_board for a repo, owner/repo, naming the crew it belongs to
  # (#29). The board id is derived from the repo. A command that names no
  # crew opens the board for its opener's crew, or the first crew for the
  # owner, who belongs to none.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.CrewName
  alias GuideCardLifecycle.IssueRef

  @enforce_keys [:board_id, :repo, :crew, :by]
  defstruct [:board_id, :repo, :crew, :by]

  @impl true
  def command_type, do: :open_board

  @impl true
  def new(%{repo: repo, by: %Actor{} = by} = params) do
    with {:ok, repo} <- IssueRef.repo(repo),
         {:ok, crew} <- CrewName.key(Map.get(params, :crew) || by.crew || CrewName.home()),
         do: {:ok, %__MODULE__{board_id: IssueRef.board_id(repo), repo: repo, crew: crew, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
