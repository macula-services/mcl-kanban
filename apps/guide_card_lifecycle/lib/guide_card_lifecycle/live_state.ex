defmodule GuideCardLifecycle.LiveState do
  # The state an aggregate holds right now, from its live process (started from
  # the store when it is not running). This is how a desk reads the crew or a
  # board before it dispatches to another stream: the aggregate is the truth,
  # not the read model, which trails it.
  @moduledoc false

  @spec of(module(), String.t()) :: term()
  def of(aggregate, stream_id) do
    store = Application.fetch_env!(:evoq, :store_id)
    {:ok, pid} = :evoq_aggregate_registry.get_or_start(aggregate, stream_id, store)
    {:ok, state} = :evoq_aggregate.get_state(pid)
    state
  end
end
