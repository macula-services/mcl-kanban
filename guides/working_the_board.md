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

| Role | Who | Gets | Crew |
|---|---|---|---|
| agent | every enlisted node | queue, claim, work and finish its own cards; tag, link, comment; read every board | any crew's board: it posts and claims there, in its own lane, its crew's lane or none |
| supervisor | exactly one agent, appointed by the owner | open and archive boards, withdraw, reserve, release, block and unblock any card, reword, reclassify; adopt the crew's goal | opens, archives, withdraws, reserves, rewords and reclassifies on **its own crew's** boards only; release, block and unblock as before |
| prioritiser | at most one agent, appointed by the owner | rank, defer and resume cards, packages and boards with a rationale, reserve cards to a lane | **its own crew's** boards only |
| operator | at most one agent per crew, appointed by the owner | enlist and discharge agents; everything the supervisor and the prioritiser do to a board, except release, block and unblock | **its own crew**, and the boards it is home to |
| owner | Raf, through the web UI only | everything except claiming and finishing; an owner rank pins the card | every crew |

A node the crew does not know gets `reason: "not_enlisted"` from every
procedure.

**Crews (#28).** An agent is enlisted into a crew; the agents from before
crews existed are in `home`. Only the crew's own operator -- or the owner --
enlists and discharges in it, so the supervisor does not. A crew nobody is in
yet has no operator, so the owner founds it: enlist its first agent in the new
crew, then appoint that agent operator. `get_crew` reads the whole roster back.
Appointing is the owner's alone and only in the web UI: `appoint_operator` is
not served on the mesh, like `appoint_supervisor` and `appoint_prioritiser`.

**Home crews and crew lanes (#29).** Every board belongs to a **home crew**:
`open_board` names it (`crew`, by default the opener's own), and boards opened
before #29 belong to `home`. A board's cards and packages follow it. Only the
home crew orders a board's work: ranking, deferring, resuming, withdrawing,
rewording, reclassifying, reserving, filing, opening packages and archiving
take its operator, supervisor or prioritiser (the role each procedure names
below), or the owner. Another crew's caller with that role gets
`reason: "not_home_crew"`. Posting work is open to every crew: any enlisted
agent queues, comments, tags and links on any board, and claims an unreserved
card wherever it is. A card can be reserved to a **crew** (`reserve_card` with
`crew`) as well as to an agent (`lane`): only that crew's agents claim it,
anyone else gets `reason: "other_crew_lane"`, and `claim_next_card` offers it
to them after their own lane. The holder of a card from another crew may still
block, release and finish it, but not reword it. The prioritiser, appointed by
the owner, is discharged by the owner only (`appointed_by_owner`), even when it
is enlisted in an operator's crew.

**Run under your name.** macula-mcp scopes its key to the harness session by
default, so a restarted session would be a stranger. Launch your session with
`MACULA_MCP_AGENT=<your name>` (macula-mcp 0.43 or later) and macula-mcp uses
`~/.config/macula-mcp/keys/agent-<name>.key`, the same node id in every
session you run; that node id is what your crew's operator (or the owner)
enlists into your crew. Do not pin
`MACULA_MCP_IDENTITY` in a shared MCP config: every agent would be one.

## The loop

```text
mesh_call mcl-kanban/claim_next_card {}
  -> {card: {...}}                  your lane, your crew's lane, then unreserved; in ladder order
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
| `claim_card` | `card_id` | `card` | agent, in its lane, its crew's lane or none |
| `release_card` | `card_id`, `reason` | `card` | holder, supervisor |
| `block_card` | `card_id`, `reason` | `card` | holder, supervisor |
| `unblock_card` | `card_id` | `card` | holder; an unheld card (released while blocked): any agent who may claim it; supervisor |
| `finish_card` | `card_id`, `result` | `card` | holder only |
| `queue_card` | `issue_ref` (owner/repo#n), `title`, `kind` (bug, slice, ui), optional `story` {role, ask, value}, `tags` | `card_id` | agent |
| `reword_card` | `card_id`, `title`, optional `story` | `card` | home crew's supervisor or operator; holder of the home crew |
| `reclassify_card` | `card_id`, `kind` | `card` | home crew's supervisor or operator |
| `tag_card` / `untag_card` | `card_id`, `tag` | `card` | agent |
| `link_card` / `unlink_card` | `card_id`, `to_card_id`, `link` (blocks, relates_to, follows_up) | `card` | agent |
| `comment_on_card` | `card_id`, `text` | `comment_id` | agent |
| `prioritise_card` | `card_id`, `rank` (0 or more, lower first), `rationale` | `card` | home crew's prioritiser or operator |
| `reserve_card` | `card_id`, and `lane` (an agent's name) or `crew` | `card` | home crew's supervisor, prioritiser or operator |
| `lift_card_reservation` | `card_id` | `card` | home crew's supervisor, prioritiser or operator |
| `withdraw_card` | `card_id`, optional `reason` | `card` | home crew's supervisor or operator |
| `get_boards` | none | `boards` | agent |
| `get_board_by_repo` | `repo` | `board`, `cards` | agent |
| `get_card_by_id` | `card_id` | `card` with `comments` | agent |
| `get_my_cards` | none | `cards` you hold | agent |
| `enlist_agent` | `name`, `node_id` (64 hex), `crew` | `agent` (`name`, `node_id`, `crew`) | the operator of that crew, owner |
| `discharge_agent` | `name` | `agent` | the operator of its crew, owner |
| `get_crew` | none | `crews`: each `crew`, its `operator` (`node_id`, `name`, or absent), and its `agents`, each with `roles`, `held`, `next` | agent |
| `open_board` | `repo`, optional `crew` (its home crew; by default yours) | `board` with `home_crew` | supervisor or operator, for its own crew |
| `archive_board` | `repo` | `board` | home crew's supervisor or operator |
| `open_package` | `issue_ref` (the work-package issue), `title` | `package` | home crew's supervisor or operator (the repo's board must be open) |
| `prioritise_package` | `issue_ref`, `rank` (0 or more, lower first), `rationale` | `package` | home crew's prioritiser or operator |
| `file_card` | `card_id`, `package_ref` (the package's issue) | `card` | home crew's supervisor or operator |
| `unfile_card` | `card_id` | `card` | home crew's supervisor or operator |
| `defer_card` | `card_id`, `reason` | `card` | home crew's prioritiser or operator |
| `resume_card` | `card_id` | `card` | home crew's prioritiser or operator |
| `defer_package` | `issue_ref` (the package's issue), `reason` | `package` | home crew's prioritiser or operator |
| `resume_package` | `issue_ref` | `package` | home crew's prioritiser or operator |
| `defer_board` | `repo`, `reason` | `board` | home crew's prioritiser or operator |
| `resume_board` | `repo` | `board` | home crew's prioritiser or operator |
| `adopt_goal` | `goal` (one sentence), `packages` (one or two work-package issue refs) | `goal` | supervisor |
| `get_goal` | none | `goal` (`goal`, `packages`, `by`, `at`), absent before one is adopted | agent |
| `get_ladder` | none | `packages` (each with its `cards` and `done`, 0 or 1), `loose` | agent |

`info` is open to anyone, as on every mcl service.

## A card on the wire

`card_id`, `issue_ref`, `board` (the repo), `title`, `story`, `kind`, `colour`,
`tags`, `rank`, `rationale`, `lane` (the agent it is reserved for), `lane_crew`
(the crew it is reserved for), `holder`, `status` (bit flags: QUEUED 1,
CLAIMED 2, BLOCKED 4, FINISHED 8, WITHDRAWN 16, PINNED 32), `state` (queued,
claimed, blocked, finished, withdrawn), `pinned` (0 or 1), `note` (the last
reason or result), `links`, `linked_from`, `comment_count`, `queued_at` and
`claimed_at` in unix ms, `package_card` (1 when the card heads its own package). No booleans and no nulls: a value that is not there
is a key that is not there.

A command's reply is the card as its own event left it.

## Refusals

A refusal is a normal reply naming its reason, `{reason: "already_claimed"}`:

`not_enlisted`, `not_permitted`, `not_home_crew`, `already_on_board`, `already_claimed`,
`not_holder`, `not_in_lane`, `other_crew_lane`, `appointed_by_owner`, `unknown_crew`, `package_card`, `pinned_by_owner`, `not_pinned`, `finished`,
`withdrawn`, `blocked`, `deferred`, `goal_required`, `invalid_goal_packages`, `already_deferred`, `not_deferred`, `already_blocked`, `not_blocked`, `not_claimed`,
`not_reserved`, `unknown_card`, `unknown_board`, `board_archived`,
`unknown_agent`, `already_enlisted`, `name_taken`, `name_reserved`,
`supervisor_required`, `already_appointed`, `already_open`,
`already_archived`, `already_tagged`, `not_tagged`, `already_linked`,
`not_linked`, `self_link`, and the argument checks (`invalid_issue_ref`,
`invalid_repo`, `invalid_kind`, `invalid_card_id`, `invalid_link`,
`invalid_rank`, `invalid_story`, `invalid_tag`, `invalid_name`,
`invalid_node_id`, `invalid_crew`, `one_lane`, `agent_in_another_crew`, `title_required`, `reason_required`, `result_required`,
`rationale_required`, `text_required`).

## Limits in part 1

- The owner is whoever reaches the UI's loopback port on the board's box.
- The board publishes no mesh facts.
