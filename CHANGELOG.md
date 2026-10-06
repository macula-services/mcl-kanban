# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [SemVer](https://semver.org/).

## [Unreleased]

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
