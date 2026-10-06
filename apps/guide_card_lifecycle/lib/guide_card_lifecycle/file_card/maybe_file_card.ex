defmodule GuideCardLifecycle.FileCard.MaybeFileCard do
  # Handler: the supervisor or the owner files a card into an open work
  # package; filing it into another package moves it. The package must be
  # open; that is checked against the package's live aggregate before dispatch.
  @moduledoc false

  alias GuideCardLifecycle.{
    Actor,
    CardAggregate,
    CardState,
    IssueRef,
    PackageAggregate,
    PackageState
  }

  alias GuideCardLifecycle.FileCard.{CardFiledV1, FileCardV1}

  @who [:supervisor, :owner]

  def handle_payload(state, payload), do: handle(state, struct(FileCardV1, payload))

  def handle(%CardState{status: status} = card, %FileCardV1{} = cmd) do
    cond do
      not Actor.allowed?(cmd.by, @who) -> {:error, :not_permitted}
      card.work_package == cmd.package_ref -> {:error, :already_filed}
      true -> {:ok, [CardFiledV1.new(cmd, status, %{work_package: cmd.package_ref})]}
    end
  end

  def dispatch(%FileCardV1{} = cmd) do
    package = PackageAggregate.current(IssueRef.package_id(cmd.package_ref))
    filed(PackageState.open?(package), cmd)
  end

  defp filed(false, _cmd), do: {:error, :unknown_package}

  defp filed(true, cmd),
    do: CardAggregate.dispatch(:file_card, cmd.card_id, FileCardV1.to_map(cmd))
end
