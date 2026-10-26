defmodule GuideCardLifecycle.PackageAggregate do
  # One work package per stream (package-<digest of owner/repo#n>): opened by
  # its board's home crew's supervisor or operator, ranked by its prioritiser
  # or operator, or the owner. A package follows its board's home crew (#29),
  # read live by dispatch/3 as CardAggregate does for cards.
  @moduledoc false

  @behaviour :evoq_aggregate

  alias GuideCardLifecycle.BoardAggregate
  alias GuideCardLifecycle.DeferPackage.MaybeDeferPackage
  alias GuideCardLifecycle.IssueRef
  alias GuideCardLifecycle.LiveState
  alias GuideCardLifecycle.OpenPackage.MaybeOpenPackage
  alias GuideCardLifecycle.PackageState
  alias GuideCardLifecycle.PrioritisePackage.MaybePrioritisePackage
  alias GuideCardLifecycle.ResumePackage.MaybeResumePackage
  alias GuideCardLifecycle.UnpinPackage.MaybeUnpinPackage

  @desks %{
    open_package: MaybeOpenPackage,
    prioritise_package: MaybePrioritisePackage,
    unpin_package: MaybeUnpinPackage,
    defer_package: MaybeDeferPackage,
    resume_package: MaybeResumePackage
  }

  @doc "The package as the live aggregate holds it now."
  @spec current(String.t()) :: PackageState.t()
  def current(package_id), do: LiveState.of(__MODULE__, package_id)

  @impl true
  def state_module, do: PackageState

  @impl true
  def init(package_id), do: {:ok, PackageState.new(package_id)}

  @impl true
  def apply(state, event), do: PackageState.apply_event(state, event)

  @impl true
  def execute(state, %{command_type: type} = p),
    do: routed(Map.get(@desks, type), on_board(state, p), p)

  def execute(_state, _payload), do: {:error, :unknown_command}

  defp on_board(package, %{home_crew: crew}) when is_binary(crew),
    do: %{package | home_crew: crew}

  defp on_board(package, _payload), do: package

  defp routed(nil, _state, _payload), do: {:error, :unknown_command}
  defp routed(desk, state, payload), do: desk.handle_payload(state, payload)

  @doc "Dispatches a package command to its package's stream."
  @spec dispatch(atom(), String.t(), map()) ::
          {:ok, non_neg_integer(), [map()]} | {:error, term()}
  def dispatch(command_type, package_id, payload) do
    # open_package brings the crew of the board it opens the package on.
    payload = Map.put_new_lazy(payload, :home_crew, fn -> board_crew(current(package_id)) end)

    :evoq_command.new(command_type, __MODULE__, package_id, payload)
    |> :evoq_router.dispatch()
  end

  defp board_crew(%PackageState{issue_ref: nil}), do: nil

  defp board_crew(%PackageState{issue_ref: ref}) do
    {:ok, %{repo: repo}} = IssueRef.parse(ref)
    BoardAggregate.current(IssueRef.board_id(repo)).home_crew
  end
end
