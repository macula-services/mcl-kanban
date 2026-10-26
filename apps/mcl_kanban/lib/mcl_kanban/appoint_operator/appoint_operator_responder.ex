defmodule MclKanban.AppointOperator.AppointOperatorResponder do
  # mcl-kanban/appoint_operator: crew, name. The owner appoints a crew's
  # operator, an agent already enlisted in that crew (#28). Replies the
  # appointment.
  @moduledoc false

  @behaviour :macula_response

  alias GuideCardLifecycle.Actor
  alias GuideCardLifecycle.AppointOperator.{AppointOperatorV1, MaybeAppointOperator}
  alias MclKanban.Wire

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_request(payload, state) do
    reply =
      with {:ok, by} <- Actor.of_caller(payload),
           {:ok, cmd} <-
             AppointOperatorV1.new(%{
               crew: Wire.arg(payload, :crew),
               name: Wire.arg(payload, :name),
               by: by
             }),
           {:ok, _version, _events} <- MaybeAppointOperator.dispatch(cmd),
           do: {:ok, %{operator: %{crew: cmd.crew, name: cmd.name}}}

    {:reply, Wire.reply(reply), state}
  end
end
