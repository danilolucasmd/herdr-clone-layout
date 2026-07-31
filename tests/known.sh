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

# --- claims must not outlive the workspace they guard -------------------------
# A popup whose workspace is closed from elsewhere is orphaned without ever
# running its trap, leaving its claim behind; herdr reuses short workspace ids,
# so that claim would silently block the next workspace handed the same one.
held() { [ -d "$(claim_dir "$1")" ] && echo yes || echo no; }
# Old enough that the sweep will consider it — the claim of a hook that died long
# ago, rather than one still being worked behind.
age() { touch -t 202001010000 "$(claim_dir "$1")"; }

claim w1; claim w2
check 'a claim is held once taken'                   yes "$(held w1)"

# The regression this age test exists for: hooks run concurrently and each holds
# its own snapshot, so a workspace created moments ago is missing from the one a
# hook that started first is carrying. Sweeping on absence alone dropped that
# live claim, handed the same new workspace to a second hook, and the layout was
# cloned behind the popup the first hook had just opened — before the user had
# answered it.
sweep_claims "$(snap_of 'w1:1:1')"
check 'a claim too young to be stale survives'       yes "$(held w2)"

age w2
sweep_claims "$(snap_of 'w1:1:1')"
check 'an old claim for a closed workspace is dropped' no  "$(held w2)"
check 'a claim for a live workspace is kept'           yes "$(held w1)"

# Age alone is not enough either: a workspace that is still there keeps its
# claim however long the build behind it has been running.
age w1
sweep_claims "$(snap_of 'w1:1:1')"
check 'an old claim for a live workspace is kept'    yes "$(held w1)"

# Sweeping on a failed snapshot would release claims that are still guarding a
# live build, so those are left exactly as they are.
claim w2; age w2
sweep_claims '{"workspaces":[]}'
check 'an empty snapshot sweeps nothing'             yes "$(held w2)"
sweep_claims 'not json'
check 'a malformed snapshot sweeps nothing'          yes "$(held w2)"
sweep_claims ''
check 'no snapshot at all sweeps nothing'            yes "$(held w2)"
unclaim w1; unclaim w2
check 'and a released claim is gone'                 no  "$(held w1)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
