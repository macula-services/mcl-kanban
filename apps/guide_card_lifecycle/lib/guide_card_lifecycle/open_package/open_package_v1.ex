defmodule GuideCardLifecycle.OpenPackage.OpenPackageV1 do
  # Command: open a work package for a GitHub issue, owner/repo#n, with its
  # title. The package and board ids are derived from the issue reference;
  # the home crew is the board's, put here by MaybeOpenPackage.dispatch/1
  # (#29), never taken from the caller.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, CardText, IssueRef}

  @enforce_keys [:package_id, :issue_ref, :title, :by]
  defstruct [:package_id, :board_id, :issue_ref, :title, :home_crew, :by]

  @impl true
  def command_type, do: :open_package

  @impl true
  def new(%{issue_ref: ref, title: title, by: %Actor{} = by}) do
    with {:ok, %{issue_ref: ref, repo: repo}} <- IssueRef.parse(ref),
         {:ok, title} <- CardText.required(title, 200, :title_required),
         do:
           {:ok,
            %__MODULE__{
              package_id: IssueRef.package_id(ref),
              board_id: IssueRef.board_id(repo),
              issue_ref: ref,
              title: title,
              by: by
            }}
  end

  def new(_), do: {:error, :missing_required_fields}

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
