#!/usr/bin/env bash
# This exists so the board fills itself: every crew agent enlisted under its
# stable node id, every open work package a card, every crew:<name> label that
# agent's lane. Run by the supervisor; idempotent, so a rerun changes nothing.
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
# Work packages: open issues labelled work-package owned by $KANBAN_ORGS.
# kind: bug or ui from a label of that name, else slice.
#
# Refusals that mean "already done" (already_enlisted, already_open,
# already_on_board) are not errors. Anything else is reported by name and the
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

# 2. The work packages, one JSON object per line.
packages=$(for org in $orgs; do
  gh search issues --owner "$org" --label work-package --state open --limit 200 \
    --json repository,number,title,labels \
    --jq '.[] | {repo: .repository.nameWithOwner, ref: "\(.repository.nameWithOwner)#\(.number)",
                 title: .title[0:200], labels: [.labels[].name]}'
done)

# 3. One board per repo with open work.
for repo in $(jq -r '.repo' <<<"$packages" | sort -u); do
  r=$(reason "$(call open_board "$(jq -nc --arg r "$repo" '{repo: $r}')")")
  case "$r" in
    "") echo "opened $repo" ;;
    already_open) ;;
    *) fail "open_board $repo: $r" ;;
  esac
done

# 4. One card per package; a crew:<name> label reserves it to that lane.
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
  [ -n "$lane" ] || continue
  id=$(card_id "$ref")
  card=$(call get_card_by_id "$(jq -nc --arg c "$id" '{card_id: $c}')")
  r=$(reason "$card")
  [ -z "$r" ] || { fail "get_card_by_id $ref ($id): $r"; continue; }
  holder=$(jq -r '.card.holder // empty' <<<"$card")
  current=$(jq -r '.card.lane // empty' <<<"$card")
  [ -z "$holder" ] || continue
  [ "${current,,}" != "${lane,,}" ] || continue
  r=$(reason "$(call reserve_card "$(jq -nc --arg c "$id" --arg l "$lane" '{card_id: $c, lane: $l}')")")
  case "$r" in
    "") echo "reserved $ref to $lane" ;;
    *) fail "reserve_card $ref to $lane: $r" ;;
  esac
done <<<"$packages"

exit $failed
