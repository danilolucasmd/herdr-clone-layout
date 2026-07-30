#!/usr/bin/env sh
# Unit tests for the dialog's routing — which new workspaces get asked where
# their panes should live, which directory the question is pre-filled with, and
# how the answer is turned back into a path. Sources both scripts for their
# functions; no herdr server, no terminal, nothing interactive.
#
#   ./tests/prompt.sh
#
# The tildes below are literal test data — the very thing expand_path and
# abbrev_path convert — so shellcheck's "use $HOME instead" note doesn't apply.
# shellcheck disable=SC2088

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)

command -v jq >/dev/null 2>&1 || {
  echo "tests: jq not found on PATH" >&2
  exit 1
}

HERDR_PLUGIN_STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/clone-layout-test.XXXXXX") || exit 1
export HERDR_PLUGIN_STATE_DIR
HERDR_CLONE_LAYOUT_LOG=0
export HERDR_CLONE_LAYOUT_LOG
trap 'rm -rf "$HERDR_PLUGIN_STATE_DIR"' EXIT INT TERM

CLONE_LAYOUT_SOURCE=1
export CLONE_LAYOUT_SOURCE
# Path is only known at runtime, and CI lints both scripts directly anyway.
# shellcheck disable=SC1091
. "$ROOT/bin/clone-layout"
unset CLONE_LAYOUT_SOURCE

CLONE_LAYOUT_DIALOG_SOURCE=1
export CLONE_LAYOUT_DIALOG_SOURCE
# shellcheck disable=SC1091
. "$ROOT/bin/clone-layout-dialog"
unset CLONE_LAYOUT_DIALOG_SOURCE

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

# A snapshot with one plain workspace, one linked worktree, and one workspace
# herdr tracks no checkout for (not every workspace is a repo).
SNAP='{
  "focused_workspace_id": "w1",
  "workspaces": [
    {"workspace_id": "w1", "tab_count": 1, "pane_count": 1,
     "worktree": {"checkout_path": "/repo", "is_linked_worktree": false}},
    {"workspace_id": "w2", "tab_count": 1, "pane_count": 1,
     "worktree": {"checkout_path": "/repo/.wt/feature", "is_linked_worktree": true}},
    {"workspace_id": "w3", "tab_count": 1, "pane_count": 1, "worktree": null}
  ],
  "panes": [
    {"pane_id": "w1:p1", "workspace_id": "w1", "cwd": "/repo/sub"},
    {"pane_id": "w3:p1", "workspace_id": "w3", "cwd": "/home/someone/notes"}
  ]
}'

yesno() { if "$@"; then echo yes; else echo no; fi; }

# --- worktrees are told apart from plain workspaces --------------------------
check 'a linked worktree is recognised'    yes "$(yesno ws_is_worktree "$SNAP" w2)"
check 'the main checkout is not a worktree' no "$(yesno ws_is_worktree "$SNAP" w1)"
check 'a non-repo workspace is not either'  no "$(yesno ws_is_worktree "$SNAP" w3)"
check 'an unknown workspace is not either'  no "$(yesno ws_is_worktree "$SNAP" wZ)"

# --- the directory the question is pre-filled with ---------------------------
check 'checkout path wins when herdr has one' /repo               "$(ws_dir "$SNAP" w1)"
check 'a worktree reports its own checkout'   /repo/.wt/feature   "$(ws_dir "$SNAP" w2)"
check 'otherwise fall back to a pane cwd'     /home/someone/notes "$(ws_dir "$SNAP" w3)"
check 'an unknown workspace has no directory' ''                  "$(ws_dir "$SNAP" wZ)"

# --- who actually gets asked -------------------------------------------------
# The dialog is for whatever the user is looking at, worktree or not: a worktree's
# directory was settled when it was created, but the two boxes were not. What
# isn't asked is anything built in the background, with nobody there to answer —
# and `apply`, which is itself an answer, so it sets the suppress flag.
check 'a focused plain workspace is asked'      yes "$(yesno should_prompt "$SNAP" w1)"
check 'an unfocused workspace is not asked'     no  "$(yesno should_prompt "$SNAP" w3)"
check 'an unfocused worktree is not either'     no  "$(yesno should_prompt "$SNAP" w2)"

# The same question, for the same reason, once the worktree is the one on screen.
SNAP_WT=$(printf '%s' "$SNAP" | jq -c '.focused_workspace_id = "w2"')
check 'a focused worktree is asked too'         yes "$(yesno should_prompt "$SNAP_WT" w2)"
check 'and the focus is what decides it'        no  "$(yesno should_prompt "$SNAP_WT" w1)"
: >"$NOPROMPT_FILE"
check 'apply suppresses the question'           no  "$(yesno should_prompt "$SNAP" w1)"
rm -f "$NOPROMPT_FILE"
check 'and it is asked again once apply is done' yes "$(yesno should_prompt "$SNAP" w1)"

# --- the remembered checkboxes -----------------------------------------------
# Only a stored "0" unticks a box, so a fresh install starts with both ticked and
# a state dir the plugin cannot write to behaves the same rather than quietly
# turning things off.
check 'both boxes start ticked'                 'yes yes' \
  "$(yesno clone_enabled) $(yesno apps_enabled)"
remember "$CLONE_BOX" 0
check 'unticking a box is remembered'           'no yes' \
  "$(yesno clone_enabled) $(yesno apps_enabled)"
remember "$APPS_BOX" 0
remember "$CLONE_BOX" 1
check 'each box is remembered on its own'       'yes no' \
  "$(yesno clone_enabled) $(yesno apps_enabled)"
remember "$APPS_BOX" 1
check 'ticking one back on is too'              'yes yes' \
  "$(yesno clone_enabled) $(yesno apps_enabled)"
printf 'garbage\n' >"$STATE/$CLONE_BOX"
check 'an unreadable answer counts as ticked'   yes "$(yesno clone_enabled)"
rm -f "$STATE/$CLONE_BOX" "$STATE/$APPS_BOX"
check 'and so does no answer at all'            'yes yes' \
  "$(yesno clone_enabled) $(yesno apps_enabled)"

# A box is drawn from the same flag the dialog acts on, so an [x] on screen can't
# disagree with what Enter is about to do.
check 'a ticked box is drawn ticked'   '[x]' "$(checkbox 1)"
check 'an unticked box is drawn empty' '[ ]' "$(checkbox 0)"

# --- turning what was typed back into a path ---------------------------------
check 'a bare tilde is the home directory'  "$HOME"          "$(expand_path '~')"
check 'a tilde path expands'                "$HOME/dotfiles" "$(expand_path '~/dotfiles')"
check 'an absolute path is left alone'      /var/tmp         "$(expand_path '/var/tmp')"
check 'a tilde mid-path is not expanded'    /opt/~/x         "$(expand_path '/opt/~/x')"
check 'home shortens back to a tilde'       '~/dotfiles'     "$(abbrev_path "$HOME/dotfiles")"
check 'home itself shortens to a tilde'     '~'              "$(abbrev_path "$HOME")"
check 'a path outside home is left alone'   /var/tmp         "$(abbrev_path '/var/tmp')"

# --- the control characters the key handling compares against ----------------
# `LF=$(printf '\n')` is the empty string, and an Enter key compared against ""
# never matches — the dialog would ignore the key that confirms it.
check 'every key constant is one byte'      '1 1 1 1 1 1 1 1 1' \
  "${#CR} ${#LF} ${#TAB} ${#ESC} ${#BS} ${#DEL} ${#NAK} ${#ETB} ${#EOT}"

# --- what the hook does with the remembered answer ---------------------------
# From here on the three things try_populate reaches out to are stand-ins, so
# the decision itself can be tested with no herdr server and no popup. Keep this
# section last: the real snapshot/do_clone/open_dialog are gone afterwards.
FOCUSED=w9
HOOK_WS='{
  "workspaces": [
    {"workspace_id": "w1", "tab_count": 3, "pane_count": 4,
     "worktree": {"checkout_path": "/repo", "is_linked_worktree": false}},
    {"workspace_id": "w9", "tab_count": 1, "pane_count": 1,
     "worktree": {"checkout_path": "/repo/.wt/a", "is_linked_worktree": true}},
    {"workspace_id": "w8", "tab_count": 1, "pane_count": 1,
     "worktree": {"checkout_path": "/repo/.wt/b", "is_linked_worktree": true}},
    {"workspace_id": "w6", "tab_count": 1, "pane_count": 1,
     "worktree": {"checkout_path": "/repo/.wt/c", "is_linked_worktree": true}},
    {"workspace_id": "w7", "tab_count": 1, "pane_count": 1, "worktree": null}
  ],
  "panes": []
}'
snapshot() { printf '%s' "$HOOK_WS" | jq -c --arg f "$FOCUSED" '.focused_workspace_id = $f'; }
do_clone()    { cloned="$2 -> $3"; }
open_dialog() { asked="$2 -> $3"; }
record_focus w1   # the workspace to clone from, as the real hook would record it

populate() { # new_ws -> "cloned|asked"
  cloned=''; asked=''
  try_populate "$1"
  unclaim "$1"
  printf '%s|%s' "$cloned" "$asked"
}

# Built in the background, with nobody looking, there is no popup to answer — so
# the box is the only say the user gets. This is also the path that settles the
# focus before deciding, since a worktree's three events all race each other.
FOCUSED=w1
remember "$CLONE_BOX" 1
check 'a background worktree clones while ticked'   'w1 -> w9|' "$(populate w9)"
remember "$CLONE_BOX" 0
check 'and is left alone once it is unticked'       '|'         "$(populate w8)"

# On screen it is asked instead, worktree or not — and an unticked box does not
# suppress that, since the popup is where the box lives and hiding it would leave
# no way to tick it back on. (The box is still unticked from just above.)
FOCUSED=w6
check 'a worktree you are looking at is asked'      '|w1 -> w6' "$(populate w6)"
FOCUSED=w7
check 'so is a plain new workspace'                 '|w1 -> w7' "$(populate w7)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
