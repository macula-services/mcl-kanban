defmodule GuideCardLifecycle.PackageEvent do
  # What every package event carries besides its own fields: the package, the
  # status after the event, who acted and when.
  @moduledoc false

  alias GuideCardLifecycle.Actor

  @spec new(String.t(), String.t(), Actor.t(), non_neg_integer(), map()) :: map()
  def new(event_type, package_id, %Actor{} = by, status, fields) do
    by
    |> Actor.record()
    |> Map.merge(%{
      event_type: event_type,
      package_id: package_id,
      status: status,
      at: System.system_time(:millisecond)
    })
    |> Map.merge(fields)
  end
end
