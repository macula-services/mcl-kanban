defmodule MclKanban.ResumePackage.ResumePackageResponder do
  # mcl-kanban/resume_package: issue_ref (the package's issue). The prioritiser or the owner resumes
  # a paused package, unranked (#17). Replies the package.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.ResumePackage.{MaybeResumePackage, ResumePackageV1}
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
           {:ok, cmd} <- ResumePackageV1.new(%{package_id: IssueRef.package_id(ref), by: by}),
           {:ok, _version, _events} <- MaybeResumePackage.dispatch(cmd),
           :ok <- GetLadder.await_deferred(cmd.package_id, 0),
           do: {:ok, %{package: %{package_id: cmd.package_id, issue_ref: ref, deferred: 0}}}

    {:reply, Wire.reply(reply), state}
  end
end
