defmodule GuideCardLifecycle.AdoptGoal.AdoptGoalV1 do
  # Command: the crew's one goal (#18): a sentence (the "this exists so..."
  # line) and the one or two work packages it covers. A new goal replaces
  # the old; ordering several things is what ranks are for.
  @moduledoc false

  @behaviour :evoq_command

  alias GuideCardLifecycle.{Actor, CardText, IssueRef}

  @enforce_keys [:goal, :packages, :by]
  defstruct [:goal, :packages, :by]

  @impl true
  def command_type, do: :adopt_goal

  @impl true
  def new(%{goal: goal, packages: packages, by: %Actor{} = by}) do
    with {:ok, goal} <- CardText.required(goal, 300, :goal_required),
         {:ok, packages} <- packages(packages),
         do: {:ok, %__MODULE__{goal: goal, packages: packages, by: by}}
  end

  def new(_), do: {:error, :missing_required_fields}

  defp packages(refs) when is_list(refs) and length(refs) in 1..2,
    do: refs |> Enum.map(&IssueRef.parse/1) |> parsed([])

  defp packages(_refs), do: {:error, :invalid_goal_packages}

  defp parsed([], acc), do: {:ok, Enum.reverse(acc)}
  defp parsed([{:ok, %{issue_ref: ref}} | rest], acc), do: parsed(rest, [ref | acc])
  defp parsed([{:error, _} = error | _rest], _acc), do: error

  @impl true
  def to_map(%__MODULE__{} = cmd),
    do: cmd |> Map.from_struct() |> Map.put(:command_type, command_type())

  def to_payload(cmd), do: to_map(cmd)
end
