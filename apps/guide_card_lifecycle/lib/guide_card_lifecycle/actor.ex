defmodule GuideCardLifecycle.Actor do
  # THE ROLE GATE: who a command acts as, and with which roles.
  #
  # A mesh call acts as its caller. macula puts the node id of the key that
  # signed the call on the payload under the ATOM key `caller`, as 32 raw
  # bytes: every station on the path checks the signature, the provider checks
  # it again before any handler runs, and macula writes it over any `caller`
  # the payload itself sent (a payload can only ever carry text keys, never
  # that atom). So the atom-keyed 32 bytes ARE proof of the signer's key, and
  # nothing else in a payload is.
  #
  # Roles come ONLY from the crew, looked up by that node id: agent for every
  # enlisted node, supervisor and prioritiser for the two appointed ones. A
  # name, a role or a caller written into the payload is never read here. A
  # node the crew does not know is refused with not_enlisted.
  #
  # The OWNER is not a mesh role. It exists only in-process, for the web UI,
  # which listens on loopback on the box that runs the board (part 1, #2).
  # No function here turns a mesh caller into the owner, and the crew refuses
  # an agent named "owner" (EnlistAgentV1), so a record's `by` cannot be
  # confused with it either.
  @moduledoc false

  alias GuideCardLifecycle.CrewAggregate
  alias GuideCardLifecycle.CrewState

  @enforce_keys [:kind, :name, :roles]
  defstruct [:kind, :name, :node_id, :roles]

  @type role :: :owner | :agent | :supervisor | :prioritiser
  @type t :: %__MODULE__{
          kind: :owner | :agent,
          name: String.t(),
          node_id: String.t() | nil,
          roles: [role()]
        }

  @doc "The owner, acting through the web UI."
  @spec owner() :: t()
  def owner, do: %__MODULE__{kind: :owner, name: "owner", node_id: nil, roles: [:owner]}

  @doc "The caller of a mesh call, as the live crew knows it."
  @spec of_caller(map()) :: {:ok, t()} | {:error, :no_caller | :not_enlisted}
  def of_caller(payload) when is_map(payload), do: from_payload(CrewAggregate.current(), payload)

  @doc "The caller of a payload, as the given crew knows it."
  @spec from_payload(CrewState.t(), map()) :: {:ok, t()} | {:error, :no_caller | :not_enlisted}
  def from_payload(%CrewState{} = crew, payload) when is_map(payload),
    do: from_crew(crew, Map.get(payload, :caller))

  @doc "The actor a signed node id (32 raw bytes) is in the crew."
  @spec from_crew(CrewState.t(), term()) :: {:ok, t()} | {:error, :no_caller | :not_enlisted}
  def from_crew(%CrewState{} = crew, <<_::256>> = node_id) do
    hex = Base.encode16(node_id, case: :lower)
    enlisted(crew, hex, Map.get(crew.agents, hex))
  end

  def from_crew(%CrewState{}, _not_a_signed_caller), do: {:error, :no_caller}

  defp enlisted(_crew, _hex, nil), do: {:error, :not_enlisted}

  defp enlisted(crew, hex, name) do
    roles =
      [:agent] ++
        appointed(crew.supervisor == hex, :supervisor) ++
        appointed(crew.prioritiser == hex, :prioritiser)

    {:ok, %__MODULE__{kind: :agent, name: name, node_id: hex, roles: roles}}
  end

  defp appointed(true, role), do: [role]
  defp appointed(false, _role), do: []

  @doc "Whether the actor holds one of the named roles. The owner passes only where :owner is named."
  @spec allowed?(t(), [role()]) :: boolean()
  def allowed?(%__MODULE__{roles: roles}, permitted), do: Enum.any?(roles, &(&1 in permitted))

  @doc "Whether the actor is the agent holding the card (a holder is always an agent)."
  @spec holds?(t(), String.t() | nil) :: boolean()
  def holds?(%__MODULE__{kind: :agent, node_id: node_id}, holder_node_id)
      when is_binary(node_id) and node_id == holder_node_id,
      do: true

  def holds?(%__MODULE__{}, _holder_node_id), do: false

  @doc "Who acted, for an event: the name, the kind (owner or agent) and the node id."
  @spec record(t()) :: %{by: String.t(), by_kind: String.t(), by_node_id: String.t() | nil}
  def record(%__MODULE__{} = actor),
    do: %{by: actor.name, by_kind: Atom.to_string(actor.kind), by_node_id: actor.node_id}
end
