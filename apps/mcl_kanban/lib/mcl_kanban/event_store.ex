defmodule MclKanban.EventStore do
  # This service's reckon-db store, opened by MclKanban.Application BEFORE
  # mcl_om:boot/1 (mcl_om opens none from 0.35, mcl-om#10), so the desks find
  # it up. The canonical wiring, as mcl-mail's mcl_mail_store: start the
  # store, wait until reckon_db lists it, start the per-store evoq
  # subscription so the projections receive every event.
  #
  # config/runtime.exs MUST carry the evoq block: the subscription reads the
  # global log through evoq and crashes on {not_configured,
  # event_store_adapter} without it.
  @moduledoc false

  require Logger
  require Record

  Record.defrecordp(
    :store_config,
    Record.extract(:store_config, from_lib: "reckon_db/include/reckon_db.hrl")
  )

  @ready_timeout_ms 30_000

  @doc "Opens the store the service describes, or stops the boot naming why."
  @spec open(map()) :: :ok
  def open(%{id: id, dir: dir, indexes: indexes, mode: mode, integrity: integrity}) do
    case ensure(id, dir, indexes, mode, integrity) do
      :ok -> :ok
      {:error, why} -> raise "mcl-kanban could not open its store #{id}: #{inspect(why)}"
    end
  end

  defp ensure(id, dir, indexes, mode, integrity) do
    with :ok <- started(id, dir, indexes, mode, integrity), do: subscribed(id)
  end

  defp started(id, dir, indexes, mode, integrity) do
    sub_dir = :filename.join(dir, Atom.to_charlist(id))
    :ok = :filelib.ensure_path(sub_dir)

    config =
      store_config(
        store_id: id,
        data_dir: sub_dir,
        mode: mode,
        indexes: indexes,
        integrity: integrity,
        writer_pool_size: 5,
        reader_pool_size: 5,
        gateway_pool_size: 1,
        options: %{}
      )

    case :reckon_db_sup.start_store(config) do
      {:ok, _pid} -> ready(id, System.monotonic_time(:millisecond) + @ready_timeout_ms)
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, {:start_store_failed, reason}}
    end
  end

  defp ready(id, deadline) do
    cond do
      listed?(id) -> :ok
      System.monotonic_time(:millisecond) > deadline -> {:error, {:store_not_ready, id}}
      true -> retry(id, deadline)
    end
  end

  defp retry(id, deadline) do
    Process.sleep(100)
    ready(id, deadline)
  end

  # reckon_db_sup can refuse the call while reckon_db is still starting; that
  # means "not listed yet", which the deadline covers.
  defp listed?(id) do
    id in :reckon_db_sup.which_stores()
  catch
    _, _ -> false
  end

  defp subscribed(id) do
    case :evoq_store_subscription.start_link(id) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, {:start_subscription_failed, reason}}
    end
  end
end
