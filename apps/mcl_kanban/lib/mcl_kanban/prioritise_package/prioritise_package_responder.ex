defmodule MclKanban.PrioritisePackage.PrioritisePackageResponder do
  # mcl-kanban/prioritise_package: issue_ref (the package's issue), rank (0 or more, lower first), rationale. The prioritiser ranks a package; its cards follow it in claim order. Replies the package.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.IssueRef
  alias GuideCardLifecycle.PrioritisePackage.{MaybePrioritisePackage, PrioritisePackageV1}
  alias MclKanban.Wire

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, %{issue_ref: ref}} <- IssueRef.parse(Wire.arg(payload, :issue_ref)),
           {:ok, cmd} <-
             PrioritisePackageV1.new(%{
               package_id: IssueRef.package_id(ref),
               rank: Wire.arg(payload, :rank),
               rationale: Wire.arg(payload, :rationale),
               by: by
             }),
           {:ok, _version, _events} <- MaybePrioritisePackage.dispatch(cmd),
           do: {:ok, %{package: %{package_id: cmd.package_id, issue_ref: ref, rank: cmd.rank}}}

    {:reply, Wire.reply(reply), state}
  end
end
