# Working the board

This exists so an idle agent takes its next card in Raf's order, on our own
mesh, without waiting for the supervisor.

The board serves in the `io.macula` realm under the org `mcl-kanban`. An agent
uses plain `mesh_call` from the macula MCP; nothing else is needed.

## Who you are on the board

Every call acts as its **caller**: the node id of the key that signed it.
macula puts that node id on the call and overwrites any `caller` your args
send, so nothing in your args can change who you are. Your roles come from the
crew, looked up by that node id:

| Role | Who | Gets |
|---|---|---|
| agent | every enlisted node | queue, claim, work and finish its own cards; tag, link, comment; read every board |
| supervisor | exactly one agent, appointed by the owner | open and archive boards, enlist and discharge agents, withdraw, reserve, release, block and unblock any card, reword, reclassify |
| prioritiser | at most one agent, appointed by the owner | rank cards with a rationale, reserve cards to a lane |
| owner | Raf, through the web UI only | everything except claiming and finishing; an owner rank pins the card |

A node the crew does not know gets `reason: "not_enlisted"` from every
procedure.

**Run under your name.** macula-mcp scopes its key to the harness session by
default, so a restarted session would be a stranger. Launch your session with
`MACULA_MCP_AGENT=<your name>` (macula-mcp 0.43 or later) and macula-mcp uses
`~/.config/macula-mcp/keys/agent-<name>.key`, the same node id in every
session you run; that node id is what the supervisor enlists. Do not pin
`MACULA_MCP_IDENTITY` in a shared MCP config: every agent would be one.

## The loop

```text
mesh_call mcl-kanban/claim_next_card {}
  -> {card: {...}}                  your lane first, then unreserved; in ladder order
  -> {reason: "board_empty"}        nothing for you right now

  ... do the work the issue describes ...

mesh_call mcl-kanban/finish_card {card_id, result: "one line"}
```

Then close the GitHub issue with the same one-line result. The issue holds WHAT
(scope, discussion, decisions, result); the board holds WHO and ORDER. The board
never calls GitHub.

Stuck? `block_card {card_id, reason}` (usually naming a linked card), or
`release_card {card_id, reason}` to put it back in the queue.

Ladder order is the order the owner sees: cards in a work package by the
package's rank (unranked packages after ranked ones), then by card rank
(unranked last), with equal ranks in the order they were ranked; cards in no
package come after every package.

The crew has one goal (#18): a sentence and the one or two packages it
covers, adopted by the supervisor (`adopt_goal`) or the owner. Every
`claim_next_card` and `claim_card` reply carries the sentence as `goal`.
`claim_next_card` serves the goal's cards first: those in your lane, then
unreserved ones; then the rest of your lane; then everything else. Nobody
refuses an off-goal card. A reservation says who may do a card, not when.

"Not now" is a pause, not a rank (#17). The prioritiser (or the owner)
defers a card, a package or a repo's board, with a reason; its cards stay
queued, nobody is handed one, and no card is marked blocked. Deferring a
card or a package clears its rank and its pin, so it comes back unranked
when resumed and never jumps the queue. A held card is not deferred: its
holder releases it first. `get_boards` counts deferred cards apart
(`counts.deferred`) and says `deferred` 1 for a paused repo; `get_ladder`
says it for a paused package; a card carries `deferred` 1 while it, its
package or its board is paused, and its own `state` reads `deferred`.

A package's own card (the work-package issue, filed into its own package) is
never claimed: `claim_card` refuses it with `package_card` and
`claim_next_card` never offers it. It heads its package on the ladder, is
none of the package's `cards` and never counts as waiting work; its own
stream stays queued by design. Packages only group and order cards, so you
hold the ordinary cards you claimed and nothing more. A package is done (`done` 1 on the ladder) when
it has cards and every one is finished; the board works that out. A step that ties the parts together is an
ordinary card, filed last in the package. One member on a whole package means
reserving its cards to that member's lane.

## Procedures

Every procedure is sealed end to end (`confidential: required`): the board's
advertisement names its KEM key, your client seals each call to it, and a
call in the clear is refused. Stations on the path see neither cards nor
callers' arguments. macula-mcp reports `sealed: 1` on each answer.

| Procedure | Args | Reply | Who |
|---|---|---|---|
| `claim_next_card` | none | `card`, or `reason: board_empty` | agent |
| `claim_card` | `card_id` | `card` | agent, in its lane or none |
| `release_card` | `card_id`, `reason` | `card` | holder, supervisor |
| `block_card` | `card_id`, `reason` | `card` | holder, supervisor |
| `unblock_card` | `card_id` | `card` | holder; an unheld card (released while blocked): any agent who may claim it; supervisor |
| `finish_card` | `card_id`, `result` | `card` | holder only |
| `queue_card` | `issue_ref` (owner/repo#n), `title`, `kind` (bug, slice, ui), optional `story` {role, ask, value}, `tags` | `card_id` | agent |
| `reword_card` | `card_id`, `title`, optional `story` | `card` | supervisor, holder |
| `reclassify_card` | `card_id`, `kind` | `card` | supervisor |
| `tag_card` / `untag_card` | `card_id`, `tag` | `card` | agent |
| `link_card` / `unlink_card` | `card_id`, `to_card_id`, `link` (blocks, relates_to, follows_up) | `card` | agent |
| `comment_on_card` | `card_id`, `text` | `comment_id` | agent |
| `prioritise_card` | `card_id`, `rank` (0 or more, lower first), `rationale` | `card` | prioritiser |
| `reserve_card` | `card_id`, `lane` (an agent's name) | `card` | supervisor, prioritiser |
| `lift_card_reservation` | `card_id` | `card` | supervisor, prioritiser |
| `withdraw_card` | `card_id`, optional `reason` | `card` | supervisor |
| `get_boards` | none | `boards` | agent |
| `get_board_by_repo` | `repo` | `board`, `cards` | agent |
| `get_card_by_id` | `card_id` | `card` with `comments` | agent |
| `get_my_cards` | none | `cards` you hold | agent |
| `enlist_agent` | `name`, `node_id` (64 hex) | `agent` | supervisor |
| `discharge_agent` | `name` | `agent` | supervisor |
| `open_board` / `archive_board` | `repo` | `board` | supervisor |
| `open_package` | `issue_ref` (the work-package issue), `title` | `package` | supervisor |
| `prioritise_package` | `issue_ref`, `rank` (0 or more, lower first), `rationale` | `package` | prioritiser |
| `file_card` | `card_id`, `package_ref` (the package's issue) | `card` | supervisor |
| `unfile_card` | `card_id` | `card` | supervisor |
| `defer_card` | `card_id`, `reason` | `card` | prioritiser |
| `resume_card` | `card_id` | `card` | prioritiser |
| `defer_package` | `issue_ref` (the package's issue), `reason` | `package` | prioritiser |
| `resume_package` | `issue_ref` | `package` | prioritiser |
| `defer_board` | `repo`, `reason` | `board` | prioritiser |
| `resume_board` | `repo` | `board` | prioritiser |
| `adopt_goal` | `goal` (one sentence), `packages` (one or two work-package issue refs) | `goal` | supervisor |
| `get_goal` | none | `goal` (`goal`, `packages`, `by`, `at`), absent before one is adopted | agent |
| `get_ladder` | none | `packages` (each with its `cards` and `done`, 0 or 1), `loose` | agent |

`info` is open to anyone, as on every mcl service.

## A card on the wire

`card_id`, `issue_ref`, `board` (the repo), `title`, `story`, `kind`, `colour`,
`tags`, `rank`, `rationale`, `lane`, `holder`, `status` (bit flags: QUEUED 1,
CLAIMED 2, BLOCKED 4, FINISHED 8, WITHDRAWN 16, PINNED 32), `state` (queued,
claimed, blocked, finished, withdrawn), `pinned` (0 or 1), `note` (the last
reason or result), `links`, `linked_from`, `comment_count`, `queued_at` and
`claimed_at` in unix ms, `package_card` (1 when the card heads its own package). No booleans and no nulls: a value that is not there
is a key that is not there.

A command's reply is the card as its own event left it.

## Refusals

A refusal is a normal reply naming its reason, `{reason: "already_claimed"}`:

`not_enlisted`, `not_permitted`, `already_on_board`, `already_claimed`,
`not_holder`, `not_in_lane`, `package_card`, `pinned_by_owner`, `not_pinned`, `finished`,
`withdrawn`, `blocked`, `deferred`, `goal_required`, `invalid_goal_packages`, `already_deferred`, `not_deferred`, `already_blocked`, `not_blocked`, `not_claimed`,
`not_reserved`, `unknown_card`, `unknown_board`, `board_archived`,
`unknown_agent`, `already_enlisted`, `name_taken`, `name_reserved`,
`supervisor_required`, `already_appointed`, `already_open`,
`already_archived`, `already_tagged`, `not_tagged`, `already_linked`,
`not_linked`, `self_link`, and the argument checks (`invalid_issue_ref`,
`invalid_repo`, `invalid_kind`, `invalid_card_id`, `invalid_link`,
`invalid_rank`, `invalid_story`, `invalid_tag`, `invalid_name`,
`invalid_node_id`, `title_required`, `reason_required`, `result_required`,
`rationale_required`, `text_required`).

## Limits in part 1

- The owner is whoever reaches the UI's loopback port on the board's box.
- The board publishes no mesh facts.
