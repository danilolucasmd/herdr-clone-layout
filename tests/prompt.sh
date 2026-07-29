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
# The dialog is for a plain workspace the user is looking at. A worktree already
# had its directory chosen; a workspace built in the background has nobody there
# to answer; and `apply` is itself an answer, so it sets the suppress flag.
check 'a focused plain workspace is asked'      yes "$(yesno should_prompt "$SNAP" w1)"
check 'a worktree is never asked'               no  "$(yesno should_prompt "$SNAP" w2)"
check 'an unfocused workspace is not asked'     no  "$(yesno should_prompt "$SNAP" w3)"
: >"$NOPROMPT_FILE"
check 'apply suppresses the question'           no  "$(yesno should_prompt "$SNAP" w1)"
rm -f "$NOPROMPT_FILE"
check 'and it is asked again once apply is done' yes "$(yesno should_prompt "$SNAP" w1)"

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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
