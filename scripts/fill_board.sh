#!/usr/bin/env bash
# This exists so the board fills itself: every crew agent enlisted under its
# stable node id, every open work package a package with its own card and its
# open sub-issues filed in it, every crew:<name> label that agent's lane. Run
# by the supervisor; idempotent, so a rerun changes nothing.
#
# Usage: fill_board.sh [Name ...]
#
# The crew is the names given, else every ROLE_<Name>.md in
# $KANBAN_ROLE_DIR (default ~/.claude/sessions). An agent's node id is the one
# its key file holds: ~/.config/macula-mcp/keys/agent-<name>.key, the key
# macula-mcp uses when launched with MACULA_MCP_AGENT=<name>. An agent without
# a key file yet is skipped (it has not run under its name); a rerun picks it up.
#
# Calls go out as the supervisor, signed with
# ~/.config/macula-mcp/keys/agent-$KANBAN_SUPERVISOR.key (default supervisor),
# through macula-cli. The supervisor must be enlisted and appointed by the
# owner first (the owner's UI).
#
# The realm key: KANBAN_REALM_KEY names a file holding io.macula's public
# realm key in hex, the same value the service runs with (MCL_REALM_KEY).
#
# Work packages: open issues labelled work-package owned by $KANBAN_ORGS. Each
# opens a package (open_package) and its issue is a card filed in it; each
# open sub-issue of it (GitHub sub-issues, any repo) is a card filed in it too.
# kind: bug or ui from a label of that name, else slice.
#
# Lanes (#19): a crew:<name> label reserves the card to that agent's lane. A
# card whose issue LOST its crew: label (the issue's events show the label
# that names its current lane being removed) has the lane lifted; a lane set
# by hand, never by a label, is left alone. A label naming nobody enlisted
# is reported as WARN and changes nothing. A card someone holds is never
# moved.
#
# Refusals that mean "already done" (already_enlisted, already_open,
# already_on_board, already_filed) are not errors. Anything else is reported by name and the
# script exits 1 after finishing the rest.
#
# Needs: gh (authenticated), jq, sha256sum, macula-cli >= 0.10.
set -euo pipefail

keys="$HOME/.config/macula-mcp/keys"
supervisor=${KANBAN_SUPERVISOR:-supervisor}
orgs=${KANBAN_ORGS:-macula-io macula-services macula-internal reckon-db-org}
role_dir=${KANBAN_ROLE_DIR:-$HOME/.claude/sessions}
realm_key=${KANBAN_REALM_KEY:-}
seeds=(
  -seed station-de-frankfurt.macula.io:4433@00cd0008ec2e72b6572b7bf6fc8b048d7fe83993faf1fc544370f2bc1eb71f85
  -seed station-de-nuremberg.macula.io:4433@00a9b4143e24ae42e5a058dd28c9aab585636acd17012cc4d418a3bb5413af22
  -seed station-de-falkenstein.macula.io:4433@00df68247d119685f94030afdb203ab7a2a105fb6093a964dbf0509a57e86435
  -seed station-fi-helsinki.macula.io:4433@004d1f470097ccf8826ce291900e882fdb1f20375e53901facaec0f23eb4efd8
  -seed station-fr-paris.macula.io:4433@0063acc4a5af409ca6b15041975128d389222c48366fb3a1dfb948da01f7ca94
  -seed station-nl-ams.macula.io:4433@000370eebafa9a89a44c9448b4796788fbff1885abd67c80d681d28cebb04b0c
)

supervisor_key="$keys/agent-${supervisor,,}.key"
[ -f "$supervisor_key" ] || {
  echo "no supervisor key at $supervisor_key: launch the supervisor with MACULA_MCP_AGENT=$supervisor first" >&2
  exit 1
}
[ -n "$realm_key" ] && [ -f "$realm_key" ] || {
  echo "set KANBAN_REALM_KEY to a file holding the io.macula realm key, in hex (MCL_REALM_KEY)" >&2
  exit 1
}

failed=0
fail() { echo "FAIL $*" >&2; failed=1; }
warn() { echo "WARN $*" >&2; }

# call <procedure> <payload json> -> the result JSON, or {"reason": "..."}
call() {
  local out
  out=$(macula-cli call -json "${seeds[@]}" -identity "$supervisor_key" \
    -realm io.macula -realm-key "@$realm_key" -payload "$2" "mcl-kanban/$1" 2>&1) || true
  jq -c 'if .ok then .data.result else {reason: ("transport: " + (.error.code // .error.message // "unknown"))} end' \
    <<<"$out" 2>/dev/null || jq -nc --arg o "$out" '{reason: ("transport: " + $o)}'
}

reason() { jq -r '.reason // empty' <<<"$1"; }

# The card's stream id, as GuideCardLifecycle.IssueRef.card_id/1 derives it.
card_id() { printf 'card-%s' "$(printf '%s' "$1" | sha256sum | cut -c1-32)"; }

# 1. The crew.
crew=("$@")
if [ ${#crew[@]} -eq 0 ]; then
  for f in "$role_dir"/ROLE_*.md; do
    [ -e "$f" ] || continue
    n=${f##*/ROLE_}; crew+=("${n%.md}")
  done
fi

for name in "${crew[@]}"; do
  key="$keys/agent-${name,,}.key"
  [ -f "$key" ] || { echo "skip $name: no key yet ($key)"; continue; }
  node_id=$(macula-cli identity -json -identity "$key" | jq -r '.data.node_id')
  r=$(reason "$(call enlist_agent "$(jq -nc --arg n "$name" --arg i "$node_id" '{name: $n, node_id: $i}')")")
  case "$r" in
    "") echo "enlisted $name ${node_id:0:12}" ;;
    already_enlisted) echo "on the crew $name ${node_id:0:12}" ;;
    name_taken) fail "$name is enlisted under another node id; discharge it, then rerun to enlist ${node_id:0:12}" ;;
    *) fail "enlist $name: $r" ;;
  esac
done

# 2. The work packages, one JSON object per line, and the cards: each
#    package's own issue and its open sub-issues, each naming its package.
packages=$(for org in $orgs; do
  gh search issues --owner "$org" --label work-package --state open --limit 200 \
    --json repository,number,title,labels \
    --jq '.[] | {repo: .repository.nameWithOwner, ref: "\(.repository.nameWithOwner)#\(.number)",
                 title: .title[0:200], labels: [.labels[].name]}'
done)

cards=$(while IFS= read -r p; do
  [ -n "$p" ] || continue
  ref=$(jq -r '.ref' <<<"$p")
  jq -c '. + {package: .ref}' <<<"$p"
  gh api "repos/${ref%#*}/issues/${ref##*#}/sub_issues" --paginate \
    --jq '.[] | select(.state == "open") |
      {repo: (.repository_url | sub("^.*/repos/"; "")), number, title: .title[0:200], labels: [.labels[].name]}' |
    jq -c --arg pkg "$ref" '{repo, ref: "\(.repo)#\(.number)", title, labels, package: $pkg}'
done <<<"$packages")

# A sub-issue that is a work package itself is filed in its own package only,
# so a rerun never moves it between the two.
own=$(jq -sc '[.[].ref]' <<<"$packages")
cards=$(jq -c --argjson own "$own" 'select(.package == .ref or (.ref | IN($own[]) | not))' <<<"$cards")

# 3. One board per repo with open work, and one package per work package.
for repo in $(jq -r '.repo' <<<"$cards" | sort -u); do
  r=$(reason "$(call open_board "$(jq -nc --arg r "$repo" '{repo: $r}')")")
  case "$r" in
    "") echo "opened $repo" ;;
    already_open) ;;
    *) fail "open_board $repo: $r" ;;
  esac
done

while IFS= read -r p; do
  [ -n "$p" ] || continue
  r=$(reason "$(call open_package "$(jq -c '{issue_ref: .ref, title: .title}' <<<"$p")")")
  case "$r" in
    "") echo "opened package $(jq -r '.ref' <<<"$p")" ;;
    already_open) ;;
    *) fail "open_package $(jq -r '.ref' <<<"$p"): $r" ;;
  esac
done <<<"$packages"

# Every card on the board as it stands, card_id -> {lane, holder}: one read,
# not one call per card.
board=$(call get_ladder '{}')
[ -z "$(reason "$board")" ] || { fail "get_ladder: $(reason "$board")"; exit 1; }
lanes=$(jq -c '[(.packages[].cards[]), (.loose[])] | map({key: .card_id, value: {lane, holder}}) | from_entries' <<<"$board")

# The crew: label that was removed from an issue and names its card's lane.
lost_label() {
  local ref=$1 lane=$2
  gh api "repos/${ref%#*}/issues/${ref##*#}/events" --paginate \
    --jq '.[] | select(.event == "unlabeled") | .label.name' |
    grep -ix "crew:$lane" | head -1 || true
}

# 4. One card per issue, filed in its package; a crew:<name> label reserves
#    it to that lane, a lost one lifts it.
while IFS= read -r p; do
  [ -n "$p" ] || continue
  ref=$(jq -r '.ref' <<<"$p")
  kind=$(jq -r 'if (.labels | index("bug")) then "bug" elif (.labels | index("ui")) then "ui" else "slice" end' <<<"$p")
  lane=$(jq -r '[.labels[] | select(startswith("crew:")) | ltrimstr("crew:")][0] // empty' <<<"$p")
  r=$(reason "$(call queue_card "$(jq -c --arg k "$kind" '{issue_ref: .ref, title: .title, kind: $k}' <<<"$p")")")
  case "$r" in
    "") echo "queued $ref ($kind)" ;;
    already_on_board) ;;
    *) fail "queue_card $ref: $r"; continue ;;
  esac
  id=$(card_id "$ref")
  package=$(jq -r '.package' <<<"$p")
  r=$(reason "$(call file_card "$(jq -nc --arg c "$id" --arg k "$package" '{card_id: $c, package_ref: $k}')")")
  case "$r" in
    "") echo "filed $ref in $package" ;;
    already_filed) ;;
    *) fail "file_card $ref in $package: $r" ;;
  esac
  # A package's own card is never claimed (#15), so a lane means nothing on it.
  [ "$ref" != "$package" ] || continue
  holder=$(jq -r --arg c "$id" '.[$c].holder // empty' <<<"$lanes")
  current=$(jq -r --arg c "$id" '.[$c].lane // empty' <<<"$lanes")
  [ -z "$holder" ] || continue

  if [ -z "$lane" ]; then
    [ -n "$current" ] && [ -n "$(lost_label "$ref" "$current")" ] || continue
    r=$(reason "$(call lift_card_reservation "$(jq -nc --arg c "$id" '{card_id: $c}')")")
    case "$r" in
      "") echo "lifted $ref from $current (crew:$current label removed)" ;;
      *) fail "lift_card_reservation $ref: $r" ;;
    esac
    continue
  fi

  [ "${current,,}" != "${lane,,}" ] || continue
  r=$(reason "$(call reserve_card "$(jq -nc --arg c "$id" --arg l "$lane" '{card_id: $c, lane: $l}')")")
  case "$r" in
    "") echo "reserved $ref to $lane" ;;
    unknown_agent) warn "$ref is labelled crew:$lane, but nobody named $lane is enlisted: left open to anyone" ;;
    *) fail "reserve_card $ref to $lane: $r" ;;
  esac
done <<<"$cards"

exit $failed
