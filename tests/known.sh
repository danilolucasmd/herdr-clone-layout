#!/usr/bin/env sh
# Unit tests for the populated-workspace history — the guard that stops a
# workspace the user has emptied out from being mistaken for a brand-new one and
# re-cloned. Sources bin/clone-layout for its functions (no herdr server, no
# terminal); each case drives remember_populated with a hand-written snapshot.
#
#   ./tests/known.sh

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)

command -v jq >/dev/null 2>&1 || {
  echo "tests: jq not found on PATH" >&2
  exit 1
}

# Sandbox the state dir so a real install's history is never touched.
HERDR_PLUGIN_STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/clone-layout-test.XXXXXX") || exit 1
export HERDR_PLUGIN_STATE_DIR
HERDR_CLONE_LAYOUT_LOG=0
export HERDR_CLONE_LAYOUT_LOG
trap 'rm -rf "$HERDR_PLUGIN_STATE_DIR"' EXIT INT TERM

CLONE_LAYOUT_SOURCE=1
export CLONE_LAYOUT_SOURCE
# Path is only known at runtime, and CI lints bin/clone-layout directly anyway.
# shellcheck disable=SC1091
. "$ROOT/bin/clone-layout"

pass=0
fail=0

check() { # description expected actual
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
    printf 'ok   %s\n' "$1"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"
  fi
}

# A snapshot carrying just the workspace counts the guard reads.
snap_of() { # "id:tabs:panes ..."
  set -- "$@"
  printf '%s' "$*" | tr ' ' '\n' | jq -R -s -c '
    {workspaces: [splits("\n") | select(length > 0) | split(":")
      | {workspace_id: .[0], tab_count: (.[1] | tonumber), pane_count: (.[2] | tonumber)}]}'
}

known_says() { # ws -> yes|no
  if ws_known "$1"; then echo yes; else echo no; fi
}

# --- a workspace only counts as populated once it holds >1 tab or >1 pane -----
remember_populated "$(snap_of 'w1:4:6' 'w2:1:1')"
check 'a populated workspace is remembered'          yes "$(known_says w1)"
check 'a fresh workspace is not remembered'          no  "$(known_says w2)"

# A second tab alone is enough, and so is a second pane alone.
remember_populated "$(snap_of 'w1:4:6' 'w2:2:2' 'w3:1:2' 'w4:1:1')"
check 'a multi-tab workspace is remembered'          yes "$(known_says w2)"
check 'a single tab with a split is remembered'      yes "$(known_says w3)"
check 'a still-fresh workspace stays eligible'       no  "$(known_says w4)"

# --- the actual bug: tearing a workspace down must not make it new again ------
remember_populated "$(snap_of 'w1:4:6' 'w2:1:1' 'w3:1:2' 'w4:1:1')"
check 'an emptied workspace is still remembered'     yes "$(known_says w2)"
remember_populated "$(snap_of 'w1:1:1' 'w2:1:1' 'w3:1:1' 'w4:1:1')"
check 'emptying every workspace remembers them all'  yes "$(known_says w1)"
check 'the emptied workspace stays remembered'       yes "$(known_says w3)"
check 'a never-populated workspace stays eligible'   no  "$(known_says w4)"

# --- herdr recycles short workspace ids, so closing one must forget it --------
remember_populated "$(snap_of 'w1:1:1' 'w4:1:1')"
check 'a closed workspace is forgotten'              no  "$(known_says w2)"
check 'a surviving workspace is kept'                yes "$(known_says w1)"
check 'a recycled id counts as new again'            no  "$(known_says w3)"

# --- a failed snapshot must not be read as "every workspace was closed" ------
# Both of these mean the server is unreachable, not that the session is empty;
# forgetting the history here would make every workspace a clone target again.
remember_populated "$(snap_of 'w1:3:3')"
remember_populated '{"workspaces":[]}'
check 'an empty snapshot leaves history intact'      yes "$(known_says w1)"
remember_populated 'not json'
check 'a malformed snapshot leaves history intact'   yes "$(known_says w1)"
remember_populated ''
check 'no snapshot at all leaves history intact'     yes "$(known_says w1)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
