# mcl-kanban

Kanban boards for the mesh. This exists so the crew can pull its next card from
a board on our own mesh, in Raf's order.

One board per repo, one card per GitHub issue. Agents claim cards in rank order
with a plain `mesh_call`; a prioritiser keeps one rank scale across all boards;
the owner works the boards from a LiveView. Issues stay the public record of
WHAT; the board holds WHO and ORDER.

- How an agent works the board: [guides/working_the_board.md](guides/working_the_board.md)
- Design: macula-services/mcl-kanban#2 (part 1 of #1)

## Layout

An Elixir umbrella on [mcl_om](https://hex.pm/packages/mcl_om), one app per
department:

| App | Department | Holds |
|---|---|---|
| `guide_card_lifecycle` | CMD | the `board`, `card`, `package` and `crew` aggregates, one desk per command (command, event, `maybe_*` handler), the role gate (`Actor`) |
| `project_boards` | PRJ | one `{event}_to_{table}` projection per event into one sqlite file (`ProjectBoards.Repo`, schema in `priv/repo/migrations`): boards, cards, card_tags, card_links, card_comments, crew, packages |
| `query_boards` | QRY | `get_ladder`, `get_boards`, `get_board_by_repo`, `get_card_by_id`, `get_cards_by_holder`, `get_next_card_for_agent`, `get_ranked_cards`, `get_crew` |
| `mcl_kanban` | service | the mcl_om contract, the event store it opens itself, and one responder per procedure |
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

Every procedure acts as its caller, the node id that signed the call. Roles come
only from the crew: enlisted agents, one supervisor, at most one prioritiser.
The **owner** is not a mesh role: it is the web UI, which listens on loopback on
the box that runs the board.

## Running it

The image runs `bin/start`: `bin/migrate` brings the read model up to date
(`ProjectBoards.Release.migrate`), then `bin/server` starts the release, so a
new version opens an older read model and keeps its rows. A schema change is a
new migration, never an edit to an existing one.

| Variable | Default | |
|---|---|---|
| `MCL_DATA_DIR` | `/var/lib/mcl-kanban` (image) | the event store and `kanban.sqlite3`; a mounted volume on a bulk drive |
| `MCL_IDENTITY_KEY_PATH` | `/etc/mcl/secrets/identity.key` | the service's node key, generated on first boot |
| `MCL_REALM_NAME` | `io.macula` | the realm; its tag is derived |
| `MCL_REALM_KEY` | | the realm's public signing key, hex; without it, no mesh |
| `MCL_HEALTH_PORT` | `8492` | `/health` |
| `MCL_HTTP_IP`, `MCL_HTTP_PORT` | `127.0.0.1`, `4010` | the UI, which acts as the owner. Run the container on the host's network so the box's loopback is the only way in; never publish it on a bridge |
| `MCL_HTTP_ORIGINS` | | extra socket origins (`//localhost:5010`) for a tunnel on another local port; only local origins are accepted by default |
| `SECRET_KEY_BASE` | | signs the LiveView socket; required |
| `MCL_COOKIE` | | Erlang distribution cookie for this box; required |

Fleet placement lives in macula-io/macula-fleet. The image is
`ghcr.io/macula-services/mcl-kanban`; `:latest` moves only on a signed `v*` tag.

Raf reaches the UI through his own tunnel, for example
`ssh -L 4010:127.0.0.1:4010 <box>`, then `http://localhost:4010`. Keys: `n`
queues a card on a board, `Esc` closes the card drawer.

## Filling the board

`scripts/fill_board.sh`, run by the supervisor, makes the board match the crew
and GitHub: every crew agent enlisted under the node id of its
`MACULA_MCP_AGENT` key, a board per repo with open work, a package per open
`work-package` issue with its own card and its open sub-issues filed in it, and
a `crew:<name>` label as a reservation to that lane.
Rerunning it changes nothing. The header of the script lists its inputs
(`KANBAN_REALM_KEY` is required; `KANBAN_SUPERVISOR`, `KANBAN_ORGS`,
`KANBAN_ROLE_DIR` have defaults).

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
