defmodule MclKanbanWeb.CardComponents do
  # The pieces both views draw: the page header, a card tile, the kind badge
  # and the refusal notice. Colour comes from the card's kind only.
  @moduledoc false

  use Phoenix.Component

  attr(:active, :string, default: "boards")
  slot(:inner_block)

  def header(assigns) do
    ~H"""
    <header class="top">
      <a class="brand" href="/" aria-label="mcl-kanban, all boards">
        <span class="logo" aria-hidden="true">▦</span> mcl-kanban
      </a>
      <nav class="crumbs">{render_slot(@inner_block)}</nav>
      <span class="who" title="This UI listens on loopback and acts as the owner">owner</span>
      <button type="button" class="theme" data-theme-toggle aria-label="Switch light or dark">◐</button>
    </header>
    """
  end

  attr(:notice, :any, default: nil)

  def notice(assigns) do
    ~H"""
    <div :if={@notice} class={"notice " <> elem(@notice, 0)} role="alert" phx-click="dismiss">
      {elem(@notice, 1)} <span class="dismiss" aria-hidden="true">×</span>
    </div>
    """
  end

  attr(:kind, :string, required: true)

  def kind(assigns) do
    ~H"""
    <span class={"kind kind-" <> @kind}>{@kind}</span>
    """
  end

  attr(:card, :map, required: true)
  attr(:show_board, :boolean, default: false)
  attr(:selected, :string, default: nil)

  def tile(assigns) do
    ~H"""
    <button
      type="button"
      class={["tile", @selected == @card.card_id && "is-selected"]}
      style={"--kind: " <> @card.colour}
      data-card-ref={@card.issue_ref}
      phx-click="select"
      phx-value-card={@card.card_id}
      aria-label={"Card " <> @card.issue_ref <> ": " <> @card.title}
    >
      <span class="tile-top">
        <.kind kind={@card.kind} />
        <span class="ref">{if @show_board, do: @card.issue_ref, else: "#" <> number(@card.issue_ref)}</span>
        <span :if={@card.rank} class="rank" title="Rank (lower is claimed first)">{@card.rank}</span>
        <span :if={@card.pinned == 1} class="pin" title="Pinned by the owner">pinned</span>
      </span>
      <span class="title">{@card.title}</span>
      <span class="tile-foot">
        <span :if={@card.holder} class="holder">◉ {@card.holder}</span>
        <span :if={@card.lane && !@card.holder} class="lane">lane {@card.lane}</span>
        <span :for={tag <- @card.tags} class="tag">{tag}</span>
        <span :if={@card.comment_count > 0} class="count" aria-label="comments">✎ {@card.comment_count}</span>
      </span>
    </button>
    """
  end

  def number(issue_ref), do: issue_ref |> String.split("#") |> List.last()

  @doc "A refusal as the notice shows it."
  def refused(reason), do: {"err", MclKanbanWeb.OwnerActions.explain(reason)}
end
