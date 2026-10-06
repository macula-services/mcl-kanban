defmodule QueryBoards.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args),
    do:
      Supervisor.start_link([QueryBoards.ReadModel],
        strategy: :one_for_one,
        name: QueryBoards.Supervisor
      )
end
