defmodule GuideCardLifecycle.AgentName do
  # What an agent's name and node id look like when a command names them.
  # "owner", "realm" and "board" are reserved: they are how an owner's, the
  # realm's and the board's own actions are recorded (#40), so no agent may
  # carry any of them. A record's `by_kind` still tells them apart from an
  # agent; the reservation keeps the audit trail from reading as something it
  # is not.
  @moduledoc false

  @name ~r/^[A-Za-z][A-Za-z0-9_-]{0,39}$/
  @node_id ~r/^[0-9a-fA-F]{64}$/
  @reserved ~w(owner realm board)

  @spec name(term()) :: {:ok, String.t()} | {:error, :invalid_name | :name_reserved}
  def name(name) when is_binary(name), do: named(Regex.match?(@name, name), name)
  def name(_), do: {:error, :invalid_name}

  defp named(false, _name), do: {:error, :invalid_name}
  defp named(true, name), do: reserved(String.downcase(name) in @reserved, name)

  defp reserved(true, _name), do: {:error, :name_reserved}
  defp reserved(false, name), do: {:ok, name}

  @spec node_id(term()) :: {:ok, String.t()} | {:error, :invalid_node_id}
  def node_id(hex) when is_binary(hex), do: hexed(Regex.match?(@node_id, hex), hex)
  def node_id(_), do: {:error, :invalid_node_id}

  defp hexed(true, hex), do: {:ok, String.downcase(hex)}
  defp hexed(false, _hex), do: {:error, :invalid_node_id}
end
