defmodule GuideCardLifecycle.AgentName do
  # What an agent's name and node id look like when a command names them.
  # "owner" is reserved: it is how every owner action is recorded, so no agent
  # may carry it.
  @moduledoc false

  @name ~r/^[A-Za-z][A-Za-z0-9_-]{0,39}$/
  @node_id ~r/^[0-9a-fA-F]{64}$/

  @spec name(term()) :: {:ok, String.t()} | {:error, :invalid_name | :name_reserved}
  def name(name) when is_binary(name), do: named(Regex.match?(@name, name), name)
  def name(_), do: {:error, :invalid_name}

  defp named(false, _name), do: {:error, :invalid_name}
  defp named(true, name), do: reserved(String.downcase(name) == "owner", name)

  defp reserved(true, _name), do: {:error, :name_reserved}
  defp reserved(false, name), do: {:ok, name}

  @spec node_id(term()) :: {:ok, String.t()} | {:error, :invalid_node_id}
  def node_id(hex) when is_binary(hex), do: hexed(Regex.match?(@node_id, hex), hex)
  def node_id(_), do: {:error, :invalid_node_id}

  defp hexed(true, hex), do: {:ok, String.downcase(hex)}
  defp hexed(false, _hex), do: {:error, :invalid_node_id}
end
