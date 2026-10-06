#!/usr/bin/env sh
# Shipped == tested: the release inside an image must carry exactly the hex
# package versions the test job resolved.
#
# Usage: assert_release_matches_lock.sh <image> <mix.lock> [lib_dir]
#
# For EVERY application in the image's release lib directory (default /app/lib)
# that the lock names as a hex package, the version must equal the lock's. Any
# mismatch fails, naming each package with both versions. Applications the lock
# does not name (the umbrella's own apps, OTP's) are not hex packages and are
# skipped; lock entries the release does not carry (dev/test-only deps) are
# skipped too.
#
# It also fails when the overlap is EMPTY: a check that compared nothing would
# pass for any image, including one built from a different resolve.
set -eu

IMAGE="${1:?image}"
LOCK="${2:?mix.lock}"
LIB="${3:-/app/lib}"

[ -s "$LOCK" ] || { echo "FAIL: lock file '$LOCK' is missing or empty" >&2; exit 1; }

# "name-version" per line, from the image's release.
shipped=$("${DOCKER:-docker}" run --rm --entrypoint ls "$IMAGE" -1 "$LIB")

# "name version" per hex entry in the lock:  "name": {:hex, :name, "1.2.3", ...
tested=$(sed -n 's/^ *"\([a-z0-9_]*\)": {:hex, :[a-z0-9_]*, "\([^"]*\)".*/\1 \2/p' "$LOCK")

echo "$tested" | SHIPPED="$shipped" awk '
  BEGIN {
    n = split(ENVIRON["SHIPPED"], entries, "\n")
    for (i = 1; i <= n; i++) {
      e = entries[i]
      # split "name-1.2.3" at the LAST "-" followed by a digit
      if (match(e, /-[0-9][^-]*$/)) { app = substr(e, 1, RSTART - 1); ver = substr(e, RSTART + 1); in_release[app] = ver }
    }
  }
  NF == 2 {
    if ($1 in in_release) {
      compared++
      if (in_release[$1] != $2) { printf "MISMATCH %s: shipped %s, tested %s\n", $1, in_release[$1], $2; bad++ }
    }
  }
  END {
    if (compared == 0) { print "FAIL: no hex package of the lock is in the release; the check compared nothing"; exit 1 }
    if (bad > 0) { printf "FAIL: %d of %d packages differ from what the tests ran on\n", bad, compared; exit 1 }
    printf "OK: all %d hex packages in the release match the tested lock\n", compared
  }'
