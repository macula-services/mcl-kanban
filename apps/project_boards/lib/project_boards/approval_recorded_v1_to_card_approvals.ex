defmodule ProjectBoards.ApprovalRecordedV1ToCardApprovals do
  # Projects approval_recorded_v1 into card_approvals: append-only, keyed by
  # card and nonce, and moves the card's version so a reply can wait for it.
  @moduledoc false

  @behaviour :evoq_event_handler

  import ProjectBoards.Projection, only: [card_update: 3, project: 3]

  @impl true
  def interested_in, do: ["approval_recorded_v1"]

  @impl true
  def replay_policy, do: :deliver

  @impl true
  def init(_config), do: {:ok, %{}}

  @impl true
  def handle_event(type, envelope, _metadata, state) do
    with {:ok, _} <- project(type, envelope, &statements/2), do: {:ok, state}
  end

  defp statements(data, version) do
    [
      {"INSERT OR IGNORE INTO card_approvals (card_id, nonce, kind, verdict, operator_node_id, repo, ref, " <>
         "base, tip, tag, issue, signed_at, recorded_by, recorded_at, approval) " <>
         "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
       [
         data.card_id,
         data.nonce,
         data.kind,
         data.verdict,
         data.operator_node_id,
         data.repo,
         data[:ref],
         data[:base],
         data[:tip],
         data[:tag],
         data[:issue],
         data.signed_at,
         data[:by],
         data.at,
         data.approval
       ]},
      card_update(data, version, [])
    ]
  end
end
