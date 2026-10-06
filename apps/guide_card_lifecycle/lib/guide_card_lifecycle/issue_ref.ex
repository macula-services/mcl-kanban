defmodule GuideCardLifecycle.IssueRef do
  # A card IS a GitHub issue on the board. The issue reference, owner/repo#n,
  # is required and names the card: the card's stream id is derived from it,
  # so a second card for the same issue lands on the same stream and is
  # refused there (already_on_board). The board's stream id is derived from
  # the repo the same way.
  #
  # Stream ids are reckon-db user ids, <prefix>-<32 hex>: the hex is the first
  # half of the sha256 of the issue reference (or repo).
  @moduledoc false

  @repo ~r/^[A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9_.-]+$/
  @ref ~r/^([A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9_.-]+)#([1-9][0-9]{0,9})$/

  @spec parse(term()) ::
          {:ok, %{issue_ref: String.t(), repo: String.t(), number: pos_integer()}}
          | {:error, :invalid_issue_ref}
  def parse(ref) when is_binary(ref), do: parsed(Regex.run(@ref, ref), ref)
  def parse(_), do: {:error, :invalid_issue_ref}

  defp parsed([_, repo, number], ref),
    do: {:ok, %{issue_ref: ref, repo: repo, number: String.to_integer(number)}}

  defp parsed(nil, _ref), do: {:error, :invalid_issue_ref}

  @spec repo(term()) :: {:ok, String.t()} | {:error, :invalid_repo}
  def repo(repo) when is_binary(repo), do: repo_ok(Regex.match?(@repo, repo), repo)
  def repo(_), do: {:error, :invalid_repo}

  defp repo_ok(true, repo), do: {:ok, repo}
  defp repo_ok(false, _repo), do: {:error, :invalid_repo}

  @spec card_id(String.t()) :: String.t()
  def card_id(issue_ref), do: "card-" <> digest(issue_ref)

  @doc "A work package's stream id, from its issue reference."
  @spec package_id(String.t()) :: String.t()
  def package_id(issue_ref), do: "package-" <> digest(issue_ref)

  @spec board_id(String.t()) :: String.t()
  def board_id(repo), do: "board-" <> digest(repo)

  @spec url(String.t()) :: String.t()
  def url(issue_ref) do
    {:ok, %{repo: repo, number: n}} = parse(issue_ref)
    "https://github.com/#{repo}/issues/#{n}"
  end

  @doc "Whether a value is a card's stream id."
  @spec card_id?(term()) :: boolean()
  def card_id?("card-" <> _ = id), do: :reckon_gater_stream_id.is_valid(id)
  def card_id?(_), do: false

  @doc "A card id a command names, or invalid_card_id."
  @spec valid_card_id(term()) :: {:ok, String.t()} | {:error, :invalid_card_id}
  def valid_card_id(id), do: card_id_ok(card_id?(id), id)

  defp card_id_ok(true, id), do: {:ok, id}
  defp card_id_ok(false, _id), do: {:error, :invalid_card_id}

  defp digest(text),
    do: :crypto.hash(:sha256, text) |> binary_part(0, 16) |> Base.encode16(case: :lower)
end
