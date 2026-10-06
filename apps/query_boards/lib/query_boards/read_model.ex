defmodule QueryBoards.ReadModel do
  # The query department's own connection to the board read model.
  # READ-ONLY BY API: only q/2 exists. project_boards owns the file and its
  # schema and starts first.
  @moduledoc false

  use GenServer

  def start_link(_),
    do: GenServer.start_link(__MODULE__, ProjectBoards.ReadModel.path(), name: __MODULE__)

  def q(sql, args), do: GenServer.call(__MODULE__, {:q, sql, args}, 10_000)

  @impl true
  def init(path) do
    {:ok, conn} = :esqlite3.open(String.to_charlist(path))
    {:ok, %{conn: conn}}
  end

  @impl true
  def handle_call({:q, sql, args}, _from, %{conn: conn} = state),
    do: {:reply, :esqlite3.q(conn, sql, args), state}

  def handle_call(:ping, _from, state), do: {:reply, :ok, state}
end
