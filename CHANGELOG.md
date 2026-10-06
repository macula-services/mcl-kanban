# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [SemVer](https://semver.org/).

## [Unreleased]

## [0.2.4] - 2026-10-06

No two members end up on the same issue through a package card (#15).

### Changed

- A package's own card (the work-package issue, filed into itself) is never
  claimed: `claim_card` refuses it with `package_card`, and `claim_next_card`
  never offers it. Packages only group and order cards; members hold
  ordinary cards. A card already holding a package card keeps it until it is
  finished or released.
- A package's own card heads its package: it is none of the package's cards
  on the ladder and never counts as waiting work (the next card, the crew's
  next card, the ranked list, the board counts in `get_boards`). The read model marks it (`package_card`, a new
  migration that also marks cards filed before this release).
- A package is done (`done` 1 in `get_ladder`) when it has cards and every
  one is finished. The board works it out; nobody claims or finishes it.

## [0.2.3] - 2026-10-06

A board fill no longer times out the mesh calls, and a dead event store no
longer reports healthy (#11).

### Fixed

- The owner UI coalesces board changes into one reload per 200 ms window.
  Before, every change reloaded every open tab at once.
- A card read fetches the tags and links of all its cards in three queries,
  instead of three per card (a ladder of 30 cards: 161 queries, now 8 or fewer).
- A command's reply waits for its version by polling the card's version
  alone, then reads the card once, instead of reading the whole card every
  15 ms.
- `/health` also asks the event store (bounded at 1 s). A store that is gone
  or stuck reports `degraded` with `event_store`, so the container goes
  unhealthy. Before, only the read model was checked.

## [0.2.2] - 2026-10-06

An upgrade keeps its data (#10). Before, the read model's schema was code
that ran CREATE ... IF NOT EXISTS at boot, so a release that changed it
crash-looped on the previous release's file until the data was wiped.

### Changed

- The read model is `ProjectBoards.Repo` (Ecto, ecto_sqlite3) and its schema
  is migrations (`apps/project_boards/priv/repo/migrations`): v0.1.0's tables,
  then v0.2.0's packages and card columns. Both adopt a file that v0.1.0 or
  v0.2.0 created from code and keep its rows.
- The image runs `bin/start` (rel/overlays): `bin/migrate`
  (`ProjectBoards.Release.migrate`) brings the read model up to date, then
  `bin/server` starts the release. A failed migration stops before anything
  reads.
- The query department reads through the same Repo; its own connection
  process is gone.

## [0.2.1] - 2026-10-06

### Fixed

- The owner's dialogs closed at the first keystroke: every live hint is a
  server render, and the patch stripped the `open` attribute the browser set,
  so Enlist could not be filled in. Dialogs now keep `open` across patches,
  and what the owner typed in any dialog is kept and drawn back on every
  render (a board change used to clear a field that had lost focus).

## [0.2.0] - 2026-10-06

The owner's ladder and work packages (#9), and the board filling itself (#6).

### Added

- Work packages: a `package` aggregate per `work-package` issue with
  `open_package` (supervisor, owner), `prioritise_package` (prioritiser, owner;
  an owner rank pins) and `unpin_package` (owner), and `file_card` /
  `unfile_card` (supervisor, owner). Mesh procedures `open_package`,
  `prioritise_package`, `file_card`, `unfile_card` and `get_ladder`.
- The read model holds `packages`, and each card's `work_package`,
  `package_rank` and `ranked_at`.
- The owner's UI is one LiveView, the rank ladder, per the approved mock
  (`docs/design/owner-ui-v2-mock.html`): packages or repos, focus, filter and
  search in the URL, drag or shift+arrows to re-rank with one owner rank
  between the neighbours (which pins, and files the card into the package it
  lands in), a reason and Undo on the toast, dialogs for enlisting, opening a
  board, queueing a card and every action that takes a reason, a per-agent
  menu on the crew rail, toasts that say how to fix a refusal, Archivo
  self-hosted, light and dark, and the full keyboard map.
- `scripts/fill_board.sh`: the supervisor fills the board from the crew and
  GitHub (#6). It enlists every crew agent by the node id of its
  `MACULA_MCP_AGENT` key, opens a board per repo with open work, opens a
  package per open `work-package` issue with the issue's card and its open
  sub-issues' cards filed in it, and reserves a card labelled `crew:<name>` to
  that agent's lane. Idempotent: a rerun changes nothing.

### Changed

- `claim_next_card` takes cards in ladder order: package rank, then card
  rank, with equal ranks in the order they were ranked; loose cards after
  every package.
- The overview and the per-repo board pages are gone; `/` is the ladder.
- The board guide tells an agent to run under `MACULA_MCP_AGENT=<name>`
  instead of pinning `MACULA_MCP_IDENTITY`, which a shared MCP config would
  give to every agent.

### Fixed

- The read model stored a missing value as the text "nil" instead of NULL: a
  released card's holder, a lifted lane and a card without a story. A card
  whose reservation was lifted kept a lane no agent matched, so nobody could
  claim it.

## [0.1.0] - 2026-10-06

The first release: part 1 of #1, the board as an mcl-om service with its web
UI, as designed in #2.

### Added

- One board per repo and one card per GitHub issue (`issue_ref` required, a
  second card for the same issue is refused `already_on_board`). Each card is
  its own event-sourced stream, so two agents claiming the same card at once
  get one card and one `already_claimed`.
- The crew: agents enlisted by name and node id, exactly one supervisor once
  founded, an optional prioritiser. Every role check uses the node id that
  signed the call; a node the crew does not know is refused `not_enlisted`.
- 26 procedures under `mcl-kanban/`, callable with a plain `mesh_call`:
  claim_next_card, claim/release/block/unblock/finish, queue/reword/reclassify,
  tags, links (blocks, relates_to, follows_up, shown both ways), comments,
  ranking with a rationale, lanes, withdraw, the four reads, and the
  supervisor's crew and board procedures. A refusal is a reply naming its
  reason.
- One rank scale across all boards. An owner rank pins the card; the
  prioritiser cannot change it until the owner unpins.
- The read model in sqlite (`project_boards`), its queries (`query_boards`),
  and the store opened by the service itself (mcl_om opens none).
- The owner's LiveView on loopback: all boards in global rank order, the crew
  and its appointments, a column view per board, and a card drawer with the
  story, tags, links, comments and the owner's actions. Colour from the
  card's kind (bug red, slice green, ui blue). Light and dark.

### Known limits

- Calls are not sealed in this first iteration (Raf's decision on #2); no
  procedure sets `confidential: required`.
- The owner is whoever reaches the UI's loopback port. Reaching it remotely
  under Raf's own identity is part 2.
- The board publishes no mesh facts; the dashboard feed is part 3.
