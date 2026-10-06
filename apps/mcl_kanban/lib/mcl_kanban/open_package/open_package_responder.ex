defmodule MclKanban.OpenPackage.OpenPackageResponder do
  # mcl-kanban/open_package: issue_ref (owner/repo#n, the work-package issue), title. The supervisor opens a work package. Replies the package.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.OpenPackage.{MaybeOpenPackage, OpenPackageV1}
  alias MclKanban.Wire

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, cmd} <-
             OpenPackageV1.new(%{
               issue_ref: Wire.arg(payload, :issue_ref),
               title: Wire.arg(payload, :title),
               by: by
             }),
           {:ok, _version, _events} <- MaybeOpenPackage.dispatch(cmd),
           do:
             {:ok,
              %{
                package: %{package_id: cmd.package_id, issue_ref: cmd.issue_ref, title: cmd.title}
              }}

    {:reply, Wire.reply(reply), state}
  end
end
