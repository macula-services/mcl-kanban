defmodule GuideCardLifecycle.PackageAggregate do
  # One work package per stream (package-<digest of owner/repo#n>): opened by
  # the supervisor or the owner, ranked by the prioritiser or the owner.
  @moduledoc false

  @behaviour :evoq_aggregate

  alias GuideCardLifecycle.DeferPackage.MaybeDeferPackage
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
  def execute(state, %{command_type: type} = p), do: routed(Map.get(@desks, type), state, p)
  def execute(_state, _payload), do: {:error, :unknown_command}

  defp routed(nil, _state, _payload), do: {:error, :unknown_command}
  defp routed(desk, state, payload), do: desk.handle_payload(state, payload)

  @doc "Dispatches a package command to its package's stream."
  @spec dispatch(atom(), String.t(), map()) ::
          {:ok, non_neg_integer(), [map()]} | {:error, term()}
  def dispatch(command_type, package_id, payload) do
    :evoq_command.new(command_type, __MODULE__, package_id, payload)
    |> :evoq_router.dispatch()
  end
end
