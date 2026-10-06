defmodule MclKanban.DeferPackage.DeferPackageResponder do
  # mcl-kanban/defer_package: issue_ref (the package's issue), reason. The prioritiser or the owner
  # pauses a package: its cards are not handed out, it loses its rank, until
  # resumed (#17). Replies the package.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.DeferPackage.{MaybeDeferPackage, DeferPackageV1}
  alias GuideCardLifecycle.IssueRef
  alias MclKanban.Wire
  alias QueryBoards.GetLadder.GetLadder

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, %{issue_ref: ref}} <- IssueRef.parse(Wire.arg(payload, :issue_ref)),
           {:ok, cmd} <-
             DeferPackageV1.new(%{
               package_id: IssueRef.package_id(ref),
               reason: Wire.arg(payload, :reason),
               by: by
             }),
           {:ok, _version, _events} <- MaybeDeferPackage.dispatch(cmd),
           :ok <- GetLadder.await_deferred(cmd.package_id, 1),
           do: {:ok, %{package: %{package_id: cmd.package_id, issue_ref: ref, deferred: 1}}}

    {:reply, Wire.reply(reply), state}
  end
end
