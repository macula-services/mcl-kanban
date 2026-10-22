"""Generate mcl-kanban's two C4 diagrams into assets/.

Run:  python3 architecture/c4_diagrams.py

  c4-context.svg     Level 1: what the service talks to
  c4-components.svg  Level 2: what it is made of

Drawn from the code, never from a template: the callbacks and the @procedures list
in apps/mcl_kanban/lib/mcl_kanban/service.ex, the app that opens the store in
application.ex, the departments and their mix.exs deps, the port, volumes and ENV
defaults in the Containerfile, and the environment config/runtime.exs reads. When one
of those changes, the diagram changes in the same commit.

Colours are plain classes with a prefers-color-scheme: dark block, no CSS custom
properties (rsvg-convert renders those black), so the SVGs render the same on
GitHub, in IDE previews and through rsvg-convert. After a change, render each
(rsvg-convert -w 1400 assets/c4-context.svg -o /tmp/c.png) and look at it; keep
architecture/README.md's tables in step.
"""
import os
from xml.sax.saxutils import escape

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")

SANS = '"Atkinson Hyperlegible", "Segoe UI", system-ui, -apple-system, Helvetica, Arial, sans-serif'
MONO = '"JetBrains Mono", ui-monospace, Menlo, Consolas, monospace'

# Element kinds, each (light fill, light stroke, dark fill, dark stroke).
KINDS = {
    "b-sys": ("#F5E9CC", "#A56F0A", "#3A2E13", "#E3AA3C"),   # in scope
    "b-per": ("#E3EBF2", "#3B5B7A", "#1D2A36", "#8EB4D8"),   # person
    "b-mac": ("#E6E4EE", "#5E5A78", "#26243A", "#A9A4C8"),   # Macula infrastructure
    "b-ext": ("#ECEFED", "#8A9791", "#1C2421", "#7D8B85"),   # external system
    "b-cmp": ("#FFFFFF", "#8A9791", "#171F1C", "#7D8B85"),   # component or container
}

STYLE = f"""<style>
.t-name {{ font-family: {SANS}; font-size: 15px; font-weight: 700; }}
.t-desc {{ font-family: {SANS}; font-size: 12.5px; }}
.t-rel {{ font-family: {SANS}; font-size: 11.5px; paint-order: stroke; stroke-width: 4px; stroke-linejoin: round; }}
.t-code {{ font-family: {MONO}; font-size: 13px; font-weight: 600; }}
.t-type {{ font-family: {MONO}; font-size: 11.5px; }}
.t-bound {{ font-family: {MONO}; font-size: 12px; font-weight: 600; }}
.t-leg {{ font-family: {SANS}; font-size: 12px; }}
.edge {{ fill: none; stroke-width: 1.25; }}
.edge-later {{ fill: none; stroke-width: 1.25; stroke-dasharray: 5 4; }}
.bg {{ fill: #FFFFFF; }}
""" + "".join(f".{k} {{ fill: {v[0]}; stroke: {v[1]}; stroke-width: {2 if k == 'b-sys' else 1.25}; }}\n" for k, v in KINDS.items()) + """\
.b-later { fill: none; stroke: #8A9791; stroke-width: 1.25; stroke-dasharray: 5 4; }
.bound { fill: none; stroke: #B3BDB8; stroke-width: 1; }
.head { fill: #3B5B7A; }
.t-name, .t-code { fill: #16201D; }
.t-type, .t-bound, .t-leg { fill: #66736E; }
.t-desc { fill: #34413C; }
.t-rel { fill: #66736E; stroke: #FFFFFF; }
.edge, .edge-later { stroke: #8A9791; }
.arrowhead { fill: #8A9791; }
@media (prefers-color-scheme: dark) {
.bg { fill: #171F1C; }
""" + "".join(f".{k} {{ fill: {v[2]}; stroke: {v[3]}; }}\n" for k, v in KINDS.items()) + """\
.b-later { stroke: #7D8B85; }
.bound { stroke: #4A5752; }
.head { fill: #8EB4D8; }
.t-name, .t-code { fill: #E6ECE9; }
.t-type, .t-bound, .t-leg { fill: #93A09A; }
.t-desc { fill: #C3CDC8; }
.t-rel { fill: #93A09A; stroke: #171F1C; }
.edge, .edge-later { stroke: #7D8B85; }
.arrowhead { fill: #7D8B85; }
}
</style>"""

DEFS = ('<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
        'orient="auto-start-reverse"><path class="arrowhead" d="M0 0L10 5L0 10z"/></marker></defs>')

LEGEND = [("b-sys", "In scope"), ("b-per", "Person"), ("b-mac", "Macula infrastructure"),
          ("b-ext", "External system"), ("b-cmp", "Container or component")]
BOUNDARY = ("bound", "Boundary")


class Diagram:
    def __init__(self, name, title, w, h):
        self.name, self.title, self.w, self.h, self.parts = name, title, w, h, []

    def text(self, cls, x, y, s, anchor=None, rotate=None):
        a = f' text-anchor="{anchor}"' if anchor else ""
        r = f' transform="rotate({rotate} {x} {y})"' if rotate is not None else ""
        self.parts.append(f'<text class="{cls}" x="{x}" y="{y}"{a}{r}>{escape(s)}</text>')

    def box(self, cls, x, y, w, h, name, kind, desc, person=False, code=False):
        # A box that is too small for its own words renders as text on top of the
        # next box, which no test would catch and a reader would read as the
        # diagram saying something it does not. Fail here instead.
        need = 70 + 16 * max(len(desc) - 1, 0) + 18
        if h < need:
            raise ValueError(f"{self.name}: {name} needs height {need}, has {h}")
        for line in desc:
            if 16 + 6.2 * len(line) > w - 16:
                raise ValueError(f"{self.name}: {name}: '{line}' is wider than {w - 32}px")
        self.parts.append(f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="10"/>')
        tx = x + 16
        if person:
            self.parts.append(f'<circle class="head" cx="{x + 26}" cy="{y + 24}" r="9"/>')
            tx = x + 44
        self.text("t-code" if code else "t-name", tx, y + 28, name)
        self.text("t-type", tx, y + 46, kind)
        for i, line in enumerate(desc):
            self.text("t-desc", x + 16, y + 70 + 16 * i, line)

    def bound(self, x, y, w, h, label):
        self.parts.append(f'<rect class="bound" x="{x}" y="{y}" width="{w}" height="{h}" rx="12"/>')
        self.text("t-bound", x + 16, y + 22, label)

    def edge(self, d, later=False):
        self.parts.append(f'<path class="{"edge-later" if later else "edge"}" d="{d}" marker-end="url(#a)"/>')

    def legend(self, y, boundary=True):
        x = 24
        for cls, label in LEGEND + ([BOUNDARY] if boundary else []):
            self.parts.append(f'<rect class="{cls}" x="{x}" y="{y}" width="22" height="14" rx="3"/>')
            self.text("t-leg", x + 30, y + 12, label)
            x += 34 + 6.6 * len(label)

    def write(self):
        svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" role="img" '
               f'aria-label="{escape(self.title)}">', f"<title>{escape(self.title)}</title>", STYLE, DEFS,
               f'<rect class="bg" x="0" y="0" width="{self.w}" height="{self.h}"/>'] + self.parts + ["</svg>", ""]
        with open(os.path.join(OUT, self.name), "w") as f:
            f.write("\n".join(svg))


def context():
    d = Diagram("c4-context.svg", "mcl-kanban system context", 1000, 690)
    d.box("b-per", 40, 30, 270, 120, "Supervisor", "[Person]",
          ["Runs scripts/fill_board.sh:", "enlists the crew and mirrors", "GitHub work into packages"],
          person=True)
    d.box("b-per", 365, 30, 270, 104, "Owner", "[Person]",
          ["Raf, through his own SSH", "tunnel to 127.0.0.1:4010"], person=True)
    d.box("b-per", 690, 30, 270, 120, "Crew agent", "[Person]",
          ["A Claude session holding a", "Macula key; claims its next", "card in rank order and works it"],
          person=True)
    d.box("b-sys", 365, 186, 270, 152, "mcl-kanban", "[mcl_om service and web UI]",
          ["Serves 39 own procedures under", "mcl-kanban/*, each a sealed call,", "and the owner's LiveView on",
           "127.0.0.1:4010. /health is a Unix", "socket, /run/mcl/health.sock"])
    d.box("b-ext", 40, 430, 270, 136, "GitHub", "[External system]",
          ["Open issues, the work-package", "label, sub-issues and", "crew:<name> lanes: read by",
           "fill_board.sh, not by the service"])
    d.box("b-mac", 365, 430, 270, 120, "macula-realm", "[Macula infrastructure]",
          ["Grants scope mcl-kanban for 30", "days to the node identity key,", "encoded from MCL_REALM_NAME"])
    d.box("b-mac", 690, 430, 270, 120, "Macula stations, mesh DHT", "[Macula infrastructure]",
          ["The service's mesh entry", "points; the DHT takes each", "capability advertisement"])
    d.edge("M175 150V430")
    d.text("t-rel", 183, 290, "runs fill_board.sh:"); d.text("t-rel", 183, 306, "reads issues with gh,")
    d.text("t-rel", 183, 322, "then calls the board")
    d.edge("M280 150V168H400V186")
    d.text("t-rel", 288, 160, "enlists, opens, files")
    d.edge("M500 134V186"); d.text("t-rel", 508, 164, "works the ladder")
    d.edge("M825 150V168H620V186")
    d.text("t-rel", 632, 160, "calls claim_next_card,"); d.text("t-rel", 632, 176, "or another procedure")
    d.edge("M460 338V430"); d.text("t-rel", 468, 384, "identity, scope")
    d.edge("M620 338V370H825V430"); d.text("t-rel", 632, 364, "advertises each procedure")
    d.text("t-desc", 40, 596, "The service calls nothing outside the mesh: GitHub is read by scripts/fill_board.sh on the supervisor's")
    d.text("t-desc", 40, 614, "machine, which then calls the board as an ordinary enlisted agent. Nothing deploys it directly either:")
    d.text("t-desc", 40, 632, "macula-fleet pins each signed v* release by digest, and no push moves a tag, so the box runs what was signed.")
    d.legend(650, boundary=False)
    d.write()


def components():
    d = Diagram("c4-components.svg", "mcl-kanban components", 1040, 1270)
    d.bound(40, 40, 968, 970, "mcl-kanban [Container]")
    d.box("b-cmp", 56, 70, 456, 120, "MclKanban.Application", "[OTP application]",
          ["start/2 opens this service's store, then calls", "mcl_om:boot(MclKanban.Service) to wire the mesh.",
           "The departments are started before it."], code=True)
    d.box("b-sys", 536, 70, 456, 120, "MclKanban.Service", "[:mcl_om_service behaviour]",
          ["info, start, stop, health, capabilities and", "identity_spec. @procedures holds the 39 names",
           "and their responders; scope is mcl-kanban."], code=True)
    d.box("b-cmp", 56, 230, 456, 120, "MclKanban.EventStore", "[Elixir module]",
          ["Opens :mcl_kanban_store under MCL_DATA_DIR via", "reckon_db_sup, waits until reckon_db lists it,",
           "then starts evoq's per-store subscription."], code=True)
    d.box("b-cmp", 536, 230, 456, 120, "ClaimNextCardResponder", "[macula_response, 1 of 39]",
          ["Card commands share MclKanban.CardProcedure:", "Actor.of_caller/1, build, dispatch, reply.",
           "This one claims down the rank ladder."], code=True)
    d.box("b-cmp", 56, 390, 456, 120, "GuideCardLifecycle", "[CMD app, umbrella]",
          ["board, card, package and crew aggregates;", "one desk per command (command, event,",
           "maybe_* handler); Actor is the role gate."], code=True)
    d.box("b-cmp", 536, 390, 456, 120, "MclKanban.Wire", "[Elixir module]",
          ["Arguments in through mcl_om_wire.field/3.", "Replies out as CBOR text, no booleans and no",
           "nulls; a refusal is %{reason: \"...\"}."], code=True)
    d.box("b-cmp", 56, 550, 456, 120, "ProjectBoards", "[PRJ app, ecto_sqlite3]",
          ["36 {event}_to_{table} projections into one", "sqlite file, kanban.sqlite3, schema in",
           "priv/repo/migrations; PubSub on write."], code=True)
    d.box("b-cmp", 536, 550, 456, 120, "MclKanban.Supervisor", "[supervisor, one_for_one]",
          ["start_link/0, called by Service.start/1.", "No children: each department supervises its",
           "own processes and macula spawns responders."], code=True)
    d.box("b-cmp", 56, 710, 456, 120, "QueryBoards", "[QRY app, umbrella]",
          ["9 read desks, one directory each:", "get_ladder, get_boards, get_card_by_id,",
           "get_next_card_for_agent and five more."], code=True)
    d.box("b-cmp", 536, 710, 456, 120, "MclKanbanWeb.Endpoint", "[Phoenix 1.8, Bandit]",
          ["Listens on 127.0.0.1:4010 and serves one", "LiveView, LadderLive. OwnerActions acts as",
           "Actor.owner() through the same desks."], code=True)
    d.box("b-mac", 56, 870, 456, 120, "mcl_om", "[library, ~> 1.4]",
          ["boot/1: loads the identity key, joins the", "realm, opens the QUIC pool, advertises the",
           "capabilities, serves /health on a socket."], code=True)
    d.box("b-mac", 536, 870, 456, 120, "macula SDK", "[library, ~> 16.0, wire 1.0]",
          ["QUIC transport, RPC dispatch to a named", "responder, and the sealed call path: every",
           "procedure is confidential: :required (PQ)."], code=True)
    d.edge("M56 130H16V930H56"); d.text("t-rel", 30, 530, "calls mcl_om:boot/1", anchor="middle", rotate=-90)
    d.edge("M512 130H536"); d.text("t-rel", 524, 122, "boots", anchor="middle")
    d.edge("M284 190V230"); d.text("t-rel", 292, 216, "opens, subscribes")
    d.edge("M804 190V230"); d.text("t-rel", 812, 216, "capabilities/0 names all 39")
    d.edge("M992 160H1008V530H804V550"); d.text("t-rel", 824, 526, "start/1 starts it")
    d.edge("M624 350V370H284V390"); d.text("t-rel", 304, 366, "Actor, command, desk")
    d.edge("M884 350V390"); d.text("t-rel", 892, 374, "shapes replies")
    d.edge("M284 510V550"); d.text("t-rel", 292, 536, "emits events")
    d.edge("M284 670V710"); d.text("t-rel", 292, 696, "the tables they read")
    d.edge("M512 610H520V690H804V710"); d.text("t-rel", 584, 686, "BoardsChanged over PubSub")
    d.edge("M536 770H512"); d.text("t-rel", 524, 762, "reads", anchor="middle")
    d.edge("M512 930H536"); d.text("t-rel", 524, 922, "dials", anchor="middle")
    d.box("b-ext", 64, 1040, 920, 120, "Host environment", "[read at boot; four are image ENV defaults]",
          ["MCL_DATA_DIR, MCL_IDENTITY_KEY_PATH, MCL_HTTP_IP and MCL_HTTP_PORT are baked into the image as ENV; a boot may override them.",
           "MCL_REALM_NAME, MCL_REALM_KEY, SECRET_KEY_BASE and MCL_COOKIE are read at boot.",
           "MCL_HTTP_ORIGINS adds socket origins and widens check_origin beyond the local defaults."],
          code=True)
    d.text("t-desc", 64, 1180, "config/runtime.exs derives the realm tag from MCL_REALM_NAME and enables kem_advertise, so callers seal to this node's KEM key.")
    d.text("t-desc", 64, 1198, "The store id, :mcl_kanban_store, is named in runtime.exs and in Service.event_store/0; a test compares the two.")
    d.text("t-desc", 64, 1216, "bin/start runs bin/migrate (ProjectBoards.Release.migrate) before bin/server, so a new release opens an older read model and keeps its rows.")
    d.legend(1240)
    d.write()


if __name__ == "__main__":
    for make in (context, components):
        make()
