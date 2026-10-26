# mcl-kanban

Kanban boards for the mesh. This exists so the crew can pull its next card from
a board on our own mesh, in Raf's order.

One board per repo, one card per GitHub issue. Agents claim cards in rank order
with a plain `mesh_call`; a prioritiser keeps one rank scale across all boards;
the owner works the boards from a LiveView. Issues stay the public record of
WHAT; the board holds WHO and ORDER.

- How an agent works the board: [guides/working_the_board.md](guides/working_the_board.md)
- Architecture (C4 model): [architecture/README.md](architecture/README.md)
- Design: macula-services/mcl-kanban#2 (part 1 of #1)

## Layout

An Elixir umbrella on [mcl_om](https://hex.pm/packages/mcl_om), one app per
department:

| App | Department | Holds |
|---|---|---|
| `guide_card_lifecycle` | CMD | the `board`, `card`, `package` and `crew` aggregates, one desk per command (command, event, `maybe_*` handler), the role gate (`Actor`) |
| `project_boards` | PRJ | one `{event}_to_{table}` projection per event into one sqlite file (`ProjectBoards.Repo`, schema in `priv/repo/migrations`): boards, cards, card_tags, card_links, card_comments, card_approvals, crew, crews, packages |
| `query_boards` | QRY | `get_ladder`, `get_boards`, `get_board_by_repo`, `get_card_by_id`, `get_cards_by_holder`, `get_goal`, `get_next_card_for_agent`, `get_ranked_cards`, `get_crew`, `get_approvals` |
| `mcl_kanban` | service | the mcl_om contract, the event store it opens itself, and a responder per procedure; mcl-om adds `mcl-kanban/info` and `mcl-kanban/get_limits` to every service, both open |
| `mcl_kanban_web` | UI | the owner's LiveView |

Every card is its own stream (`card-<digest of owner/repo#n>`), so claims on one
card are serialised: two agents claiming at once get one card and one
`already_claimed`. Status is bit flags (`card_status`: QUEUED 1, CLAIMED 2,
BLOCKED 4, FINISHED 8, WITHDRAWN 16, PINNED 32).

Work packages group cards: a GitHub issue labelled `work-package` is a package
(`package-<digest of owner/repo#n>`), ranked on its own scale by the
prioritiser, and its cards (its own issue and its sub-issues, from any repo)
are filed in it. Agents claim in ladder order: package rank, then card rank.

## The owner's UI

One LiveView, the rank ladder, as drawn in the approved mock
[docs/design/owner-ui-v2-mock.html](docs/design/owner-ui-v2-mock.html): cut by
work package or by repo, with the crew on duty beside it and a card drawer.
Drag a card, or select it with `j`/`k` and move it with shift+arrows: it lands
between its neighbours with one owner rank, which pins it. Enlisting, opening a
board, queueing a card and every action that needs a reason are dialogs; `?`
lists every key. Archivo is self-hosted under the SIL Open Font License
(`apps/mcl_kanban_web/assets/fonts/OFL.txt`).

## Roles

A call acts as its caller, the node id that signed the call. Roles come
only from the crew: enlisted agents, one supervisor, at most one prioritiser,
and the operator of the crew the agent belongs to.
The **owner** is not a mesh role: it is the web UI on `:4010` -- loopback by
default, and the box that runs the board sets `MCL_HTTP_IP=0.0.0.0`, so it is
served on the LAN with no login.

## Crews and operators

The board holds more than one crew. Each agent is enlisted **into a crew**
(`agent_enlisted_v1` carries it), and each crew has at most one **operator**
(`operator_appointed_v1`): the agent that runs it. Enlisting and discharging
belong to that crew's own operator, or to the owner -- not to the supervisor,
and never to an agent of another crew. An operator that can hand its own crew
on would let a crew pass itself along without anyone outside it agreeing, so
appointing one is the owner's alone.

- `enlist_agent` takes `name`, `node_id` and `crew`; `discharge_agent` is the
  rest of the roster on the mesh. Appointing an operator is the owner's, in the
  web UI only: it is not served on the mesh.
- `get_crew` answers `%{crews: [%{crew, operator, agents}]}`, each agent with
  its `roles`, the cards it holds and its `next` card. Enlisted callers only,
  like every read.
- Agents enlisted before crews existed are in the crew named `home`: their
  events are left as they were, and the read model reads them as `home`.
- A crew nobody is in yet has no operator to enlist into it, so the **owner
  founds it**: enlist the first agent into the new crew, then appoint it
  operator -- the enlist dialog does both in one step.

Every board has a **home crew** (#29), named by `open_board` and by default
the opener's own; boards from before are `home`'s. Only the home crew ranks,
defers, withdraws, rewords, reserves, files or archives on a board, so another
crew cannot reorder our work; any crew still queues, comments, tags, links and
claims unreserved cards there. A card can be reserved to a crew's lane
(`reserve_card` with `crew`), claimed by that crew's agents only. The rules,
role by role, are in [guides/working_the_board.md](guides/working_the_board.md).

`scripts/fill_board.sh` enlists every agent into `KANBAN_CREW` (default
`home`). It signs as `KANBAN_SUPERVISOR` (default `supervisor`), which must
therefore be both the board's supervisor and the appointed operator of that
crew: the owner appoints it, since the owner itself is never a mesh caller.

## Signed approvals

A crew's yes to a push, a tag or a planning gate is a record on the card that
any crew can check (#30), not a word in a chat or a label only our GitHub org
can set. The operator of the card's **home crew** signs a `crew-approval/v1`
with its node's identity key; any enlisted agent brings it to the board with
`record_approval`, and `get_approvals` hands every approval on a card back,
each with the signed object so the reader re-verifies it instead of trusting
this board.

The object is a [`macula_signed_object`](https://hex.pm/packages/macula) under
the label `crew-approval/v1` that carries the signer's key, encoded as CBOR and
sent as standard base64 text. Its fields, all text keys:

| Field | Value |
|---|---|
| `kind` | `range`, or a planning gate: `gate:vision`, `gate:boundary`, `gate:design` |
| `card_id` | the card the approval is on |
| `operator_node_id` | the signer's node id, 64 lowercase hex digits |
| `repo` | `org/repo`, the card's repo |
| `verdict` | `1` (yes) or `0` (no); never a boolean |
| `at` | when it was signed, ms since the epoch |
| `nonce` | 32 lowercase hex digits, fresh for every approval |
| `ref`, `base`, `tip` | a `range` only: the ref and the two commits, 7 to 64 hex digits |
| `tag` | a `range` only, optional: the tag it releases |
| `issue` | a gate only: the plan issue it passes, `org/repo#n` |

No other field is accepted. The board records an approval only when all of
these hold, and otherwise answers the reason:

1. the object decodes, is the shape of its kind, and its signature verifies
   over the label, the carried key and the fields as signed
   (`approval_malformed`, `signature_invalid`, `alg_mismatch`);
2. `operator_node_id` is the node id of the key that signed (`signer_mismatch`);
3. it names this card and this card's repo (`wrong_card`, `wrong_repo`);
4. its signer is, right now, the appointed operator of the crew the card's
   board belongs to (`not_home_operator`): an agent's key and another crew's
   operator are refused alike, and once the owner hands a board over, its old
   operator's approvals stop counting;
5. its nonce has not been recorded on this card before (`replayed_nonce`).
   Signing `card_id` is what makes a per-card nonce enough: the same yes
   brought to another card is `wrong_card`.

A no (`verdict` 0) is recorded like a yes, and an approval is accepted on a
finished card, since a release is often approved once its card is done. To
check one yourself, decode the base64, run `macula_signed_object:verify/3` with
the label `crew-approval/v1`, derive the node id from the returned key
(`macula_node_keys:node_id/2`), and compare it with `operator_node_id` and
with the operator `get_crew` names for the card's home crew.
`GuideCardLifecycle.RecordApproval.CrewApproval.sign/2` signs one from an
identity key, field for field as above.

## Running it

The image runs `bin/start`: `bin/migrate` brings the read model up to date
(`ProjectBoards.Release.migrate`), then `bin/server` starts the release, so a
new version opens an older read model and keeps its rows. A schema change is a
new migration, never an edit to an existing one.

`/health` is `ok` only while both the read model and the event store answer;
either one failing reports `degraded`, naming it (`read_model`, `event_store`).

| Variable | Default | |
|---|---|---|
| `MCL_DATA_DIR` | `/var/lib/mcl-kanban` (image) | the event store and `kanban.sqlite3`; a mounted volume on a bulk drive |
| `MCL_IDENTITY_KEY_PATH` | `/etc/mcl/secrets/identity.key` | the service's node key, generated on first boot |
| `MCL_REALM_NAME` | `io.macula` | the realm; its tag is derived |
| `MCL_REALM_KEY` | | the realm's public signing key, hex; without it, no mesh |
| `MCL_HTTP_IP`, `MCL_HTTP_PORT` | `127.0.0.1`, `4010` | the UI, which acts as the owner. Run the container on the host's network so the box's loopback is the only way in; never publish it on a bridge |
| `MCL_HTTP_ORIGINS` | | extra socket origins (`//localhost:5010`) for a tunnel on another local port; only local origins are accepted by default |
| `SECRET_KEY_BASE` | | signs the LiveView socket; required |
| `MCL_COOKIE` | | Erlang distribution cookie for this box; required |

Fleet placement lives in macula-io/macula-fleet. The image is
`ghcr.io/macula-services/mcl-kanban`; nothing moves `:latest`: macula-fleet pins each
signed `v*` release by digest (macula-fleet#14, #15).

The board's UI is at `http://<box>:4010`, on the LAN, with no login; where the box
is not reachable, `ssh -L 4010:127.0.0.1:4010 <box>` and `http://localhost:4010`
reach the same UI. Keys: `n`
queues a card on a board, `Esc` closes the card drawer.

## Filling the board

`scripts/fill_board.sh` makes the board match the crew and GitHub: every crew
agent enlisted into `KANBAN_CREW` under the node id of its
`MACULA_MCP_AGENT` key, a board per repo with open work, a package per open
`work-package` issue with its own card and its open sub-issues filed in it, and
a `crew:<name>` label as a reservation to that lane.
Rerunning it changes nothing. The header of the script lists its inputs
(`KANBAN_REALM_KEY` is required; `KANBAN_SUPERVISOR`, `KANBAN_CREW`,
`KANBAN_ORGS`, `KANBAN_ROLE_DIR` have defaults).

## Development

The gates run in the CI image (`.github/workflows/ci.yml`), the same image the
Containerfile builds in:

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix credo
mix test
mix dialyzer
```

## Licence

Apache-2.0.
