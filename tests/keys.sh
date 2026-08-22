#!/usr/bin/env sh
# End-to-end tests for the dialog's key handling — the popup driven the way a
# keyboard drives it, with the keys arriving on stdin instead of from a terminal
# and a stub herdr standing in for a session. Each case checks what an answer
# decides: whether a layout is cloned, where its panes open, what is remembered
# for the next new workspace, and whether the workspace survives being cancelled.
#
#   ./tests/keys.sh
#
# stdin is a file rather than a tty, so every stty call inside the dialog fails
# harmlessly and the reads come back a byte at a time all the same. Nothing here
# needs a terminal, a herdr server, or a real workspace.

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
DIALOG="$ROOT/bin/clone-layout-dialog"

command -v jq >/dev/null 2>&1 || {
  echo "tests: jq not found on PATH" >&2
  exit 1
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/clone-layout-keys.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

# The directory the popup offers, and the one it has to find on disk when the
# directory row is confirmed.
DIR="$TMP/repo"
mkdir -p "$DIR"

# A herdr standing in for a session holding one workspace: w7, the fresh one the
# popup is being asked about. $WS_STATE picks what the popup finds if it goes to
# close it on the way out — an untouched workspace, one that has grown a second
# tab since, or one whose pane is running something. Every `workspace close` is
# recorded in $CLOSED, which is how the cancel cases below are checked.
cat >"$TMP/herdr" <<'STUB'
#!/usr/bin/env sh
counts='"tab_count":1,"pane_count":1'
[ "${WS_STATE:-idle}" = dirty ] && counts='"tab_count":2,"pane_count":2'
# $WS_KIND makes w7 a linked worktree instead of a plain workspace.
wt=null
[ "${WS_KIND:-workspace}" = worktree ] &&
  wt='{"checkout_path":"/repo/.wt/x","is_linked_worktree":true}'
case "$1 $2" in
  "api snapshot")
    printf '{"result":{"snapshot":{"focused_workspace_id":"w7","workspaces":[{"workspace_id":"w7",%s,"worktree":%s}],"tabs":[{"workspace_id":"w7","tab_id":"w7:t1","label":""}],"panes":[{"pane_id":"w7:p1","workspace_id":"w7","tab_id":"w7:t1","cwd":"/tmp"}],"layouts":[]}}}\n' "$counts" "$wt"
    ;;
  "pane process-info")
    if [ "${WS_STATE:-idle}" = busy ]; then
      printf '{"result":{"process_info":{"pane_id":"w7:p1","shell_pid":10,"foreground_process_group_id":77,"foreground_processes":[{"cmdline":"nvim .","pid":77}]}}}\n'
    else
      printf '{"result":{"process_info":{"pane_id":"w7:p1","shell_pid":10,"foreground_process_group_id":10,"foreground_processes":[{"cmdline":"/bin/sh","pid":10}]}}}\n'
    fi
    ;;
  "workspace close") printf '%s\n' "$3" >>"$CLOSED" ;;
  *) : ;;
esac
STUB
chmod +x "$TMP/herdr"

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

# The keys, named so the cases below read like the keystrokes they are.
UP=$(printf '\033[A')
DOWN=$(printf '\033[B')
ENTER=$(printf '\r')
TAB=$(printf '\t')
ESC=$(printf '\033')
SPACE=' '
BS=$(printf '\010')       # ctrl-backspace, as a terminal sends it
DEL=$(printf '\177')      # plain backspace
CTRLW=$(printf '\027')
CTRLU=$(printf '\025')

# Types the keys into a fresh popup and reports what it decided, as
# "<log>|<clone box>|<apps box>|<recorded as done>|<workspace closed>". The two
# optional arguments seed the boxes, standing in for a popup answered earlier.
answer() { # keys [stored_clone_box] [stored_apps_box]
  state=$TMP/state
  rm -rf "$state"
  mkdir -p "$state"
  WS_STATE=${WS_STATE:-idle}
  WS_KIND=${WS_KIND:-workspace}
  export WS_STATE WS_KIND
  [ -n "${2:-}" ] && printf '%s\n' "$2" >"$state/clone-enabled"
  [ -n "${3:-}" ] && printf '%s\n' "$3" >"$state/reopen-apps"
  printf '%s' "$1" >"$TMP/keys"
  CLOSED=$state/closed
  export CLOSED

  # The hook decides the kind from the same snapshot the stub is serving, so a
  # worktree in $WS_KIND is a worktree to the popup too — which is what takes the
  # directory row out of it.
  HERDR_PLUGIN_STATE_DIR=$state \
  HERDR_PLUGIN_ROOT=$ROOT \
  HERDR_BIN_PATH=$TMP/herdr \
  CLONE_LAYOUT_TARGET=w7 \
  CLONE_LAYOUT_FROM=w1 \
  CLONE_LAYOUT_DIR=$DIR \
  CLONE_LAYOUT_KIND=$WS_KIND \
    sh "$DIALOG" <"$TMP/keys" >/dev/null 2>&1

  printf '%s|%s|%s|%s|%s' \
    "$(sed -n 's/^[0-9:]* dialog: //p' "$state/clone-layout.log" 2>/dev/null | head -n 1)" \
    "$(cat "$state/clone-enabled" 2>/dev/null || echo '(unset)')" \
    "$(cat "$state/reopen-apps" 2>/dev/null || echo '(unset)')" \
    "$(cat "$state/populated-workspaces" 2>/dev/null || echo '(none)')" \
    "$(cat "$state/closed" 2>/dev/null || echo '(none)')"
}

# --- the two directory answers, with both boxes left ticked ------------------
check 'enter clones as-is, as it always has' \
  "clone w1 -> w7 as-is|1|1|w7|(none)"    "$(answer "$ENTER")"
check 'the directory row clones into it' \
  "clone w1 -> w7 in $DIR|1|1|w7|(none)"  "$(answer "$DOWN$ENTER")"
check 'confirming on a box clones as-is' \
  "clone w1 -> w7 as-is|1|1|w7|(none)"    "$(answer "$DOWN$DOWN$ENTER")"
# Tab is completion on the directory row, so it moves down onto that row once
# and then stays there: $DIR completes to itself with the slash that would take
# the next Tab into it, and there is nothing under it to go into.
check 'tab completes on the directory row instead of moving on' \
  "clone w1 -> w7 in $DIR/|1|1|w7|(none)" "$(answer "$TAB$TAB$TAB$TAB$ENTER")"
check 'tab still moves between the rows that have no field' \
  "clone w1 -> w7 as-is|1|0|w7|(none)"    "$(answer "$DOWN$DOWN$TAB$SPACE$ENTER")"

# --- unticking the first box, then confirming above it -----------------------
# The boxes are rows of their own, so the flow is: down to one, space, back up to
# one of the two directory answers, enter. Whichever of the two you come back to,
# an unticked first box means nothing is cloned.
check 'unticked, confirmed from the top row' \
  "clone off, leaving w7 as it is|0|1|w7|(none)" "$(answer "$DOWN$DOWN$SPACE$UP$UP$ENTER")"
check 'unticked, confirmed from the directory row' \
  "clone off, leaving w7 as it is|0|1|w7|(none)" "$(answer "$DOWN$DOWN$SPACE$UP$ENTER")"
check 'ticking it back on clones again' \
  "clone w1 -> w7 as-is|1|1|w7|(none)"    "$(answer "$DOWN$DOWN$SPACE$SPACE$UP$UP$ENTER")"

# --- the second box, one row further down ------------------------------------
# It doesn't change what Enter does, only what the clone copies, so the log line
# is the same either way and the remembered answer is what moves.
check 'unticking the apps box still clones' \
  "clone w1 -> w7 as-is|1|0|w7|(none)"    "$(answer "$DOWN$DOWN$DOWN$SPACE$ENTER")"
check 'a stored no opens the apps box unticked' \
  "clone w1 -> w7 as-is|1|0|w7|(none)"    "$(answer "$ENTER" '' 0)"
check 'and space on it ticks it back on' \
  "clone w1 -> w7 as-is|1|1|w7|(none)"    "$(answer "$DOWN$DOWN$DOWN$SPACE$ENTER" '' 0)"
check 'both boxes are written by one enter' \
  "clone off, leaving w7 as it is|0|0|w7|(none)" \
  "$(answer "$DOWN$DOWN$SPACE$DOWN$SPACE$ENTER")"

# --- what the boxes remember -------------------------------------------------
check 'a stored no opens the popup unticked' \
  "clone off, leaving w7 as it is|0|1|w7|(none)" "$(answer "$ENTER" 0)"
check 'and space on the box undoes it' \
  "clone w1 -> w7 as-is|1|1|w7|(none)"    "$(answer "$DOWN$DOWN$SPACE$ENTER" 0)"

# --- esc decides nothing, and takes the workspace with it --------------------
# Cancelling means the new workspace wasn't wanted, so it goes rather than being
# left behind empty. It still decides nothing about the boxes.
check 'esc closes the workspace it was asked about' \
  "cancelled for w7|(unset)|(unset)|(none)|w7"  "$(answer "$ESC")"
check 'ctrl-d does the same' \
  "cancelled for w7|(unset)|(unset)|(none)|w7"  "$(answer "$(printf '\004')")"
check 'esc after unticking leaves both boxes as they were' \
  "cancelled for w7|(unset)|(unset)|(none)|w7" \
  "$(answer "$DOWN$DOWN$SPACE$DOWN$SPACE$ESC")"

# But only an untouched workspace: the popup doesn't hold the keyboard hostage,
# and whatever someone put in there while it was up is theirs, not ours to close.
# Anything kept is recorded as settled, so Esc isn't asked again about it.
check 'a workspace that grew a tab meanwhile is kept' \
  "cancelled for w7|(unset)|(unset)|w7|(none)" \
  "$(WS_STATE=dirty answer "$ESC")"
check 'so is one whose pane is running something' \
  "cancelled for w7|(unset)|(unset)|w7|(none)" \
  "$(WS_STATE=busy answer "$ESC")"

# A worktree is never closed by cancelling, empty or not: it is a checkout on
# disk with a branch of its own, which a dismissed popup is no reason to remove.
check 'esc leaves a worktree alone' \
  "cancelled for w7|(unset)|(unset)|w7|(none)" \
  "$(WS_KIND=worktree answer "$ESC")"
check 'and ctrl-d leaves it alone too' \
  "cancelled for w7|(unset)|(unset)|w7|(none)" \
  "$(WS_KIND=worktree answer "$(printf '\004')")"
# Confirming still works the same for one — the boxes are the point of asking.
check 'a worktree still clones on enter' \
  "clone w1 -> w7 as-is|1|1|w7|(none)" \
  "$(WS_KIND=worktree answer "$ENTER")"

# --- a worktree has no directory row -----------------------------------------
# Its directory was settled when the checkout was made, so the only question left
# is what a clone copies: the two boxes sit one row below the top instead of
# three, and there is nothing between them and it.
check 'the first box is one row down for a worktree' \
  "clone off, leaving w7 as it is|0|1|w7|(none)" \
  "$(WS_KIND=worktree answer "$DOWN$SPACE$UP$ENTER")"
check 'and the apps box is the row after that' \
  "clone w1 -> w7 as-is|1|0|w7|(none)" \
  "$(WS_KIND=worktree answer "$DOWN$DOWN$SPACE$ENTER")"
check 'down stops on the last box' \
  "clone w1 -> w7 as-is|1|0|w7|(none)" \
  "$(WS_KIND=worktree answer "$DOWN$DOWN$DOWN$DOWN$SPACE$ENTER")"
# Three tabs is all the way round and back to the top, where space toggles
# nothing — a fourth row would still be a box under this one.
check 'tab wraps round three rows, not four' \
  "clone w1 -> w7 as-is|1|1|w7|(none)" \
  "$(WS_KIND=worktree answer "$TAB$TAB$TAB$SPACE$ENTER")"
# With nowhere for a path to go, typing one is not an answer to anything: the
# keys are dropped and Enter clones as-is, rather than landing on a directory row
# that isn't on screen and failing to find what was typed.
check 'typing a path does nothing without the row' \
  "clone w1 -> w7 as-is|1|1|w7|(none)" \
  "$(WS_KIND=worktree answer "/nowhere/at/all$ENTER")"

# A popup that never got an answer at all decides nothing either way — the
# workspace stays, because nobody said they didn't want it.
check 'an abandoned popup closes nothing' \
  "stdin closed for w7|(unset)|(unset)|(none)|(none)" "$(answer '')"

# --- space belongs to the row it is standing on ------------------------------
# The top row has two boxes below it and no way to say which one is meant, so
# space does nothing there rather than guessing.
check 'space on the top row changes nothing' \
  "clone w1 -> w7 as-is|1|1|w7|(none)"    "$(answer "$SPACE$ENTER")"
# On the directory row a space is a character, so it lands in the path and the
# popup stays open on a directory that isn't there — deciding nothing.
check 'space on the directory row types a space' \
  "stdin closed for w7|(unset)|(unset)|(none)|(none)" "$(answer "$DOWN$SPACE$ENTER")"

# --- a directory that isn't there is not an answer ---------------------------
check 'a bad path keeps the popup open' \
  "stdin closed for w7|(unset)|(unset)|(none)|(none)" "$(answer "${DOWN}/nowhere/at/all$ENTER")"

# --- editing the path: the two backspaces are two different keys -------------
# The field opens on $DIR, so a case that types something and takes it back
# again lands on a directory that is there, and the log line says so. Backspace
# is a character at a time: five of them undo the five that were typed, and one
# would not have been enough if it had eaten the segment instead.
check 'backspace deletes one character' \
  "clone w1 -> w7 in $DIR|1|1|w7|(none)" \
  "$(answer "$DOWN/nope$DEL$DEL$DEL$DEL$DEL$ENTER")"
# Ctrl-backspace arrives as 010 rather than 0177, and takes a word: "nope" goes
# and the slash it hung off stays, which is still $DIR to confirm into.
check 'ctrl-backspace deletes a word' \
  "clone w1 -> w7 in $DIR/|1|1|w7|(none)" \
  "$(answer "$DOWN/nope$BS$ENTER")"
# Ctrl-W is the bigger unit — the whole segment, slash and all — so the same
# keystrokes land one character further back.
check 'ctrl-w takes the segment instead' \
  "clone w1 -> w7 in $DIR|1|1|w7|(none)" \
  "$(answer "$DOWN/nope$CTRLW$ENTER")"
# A word, not a character: one press takes back the whole of "repo", leaving
# $TMP with the slash still on it.
check 'ctrl-backspace on a bare name takes all of it' \
  "clone w1 -> w7 in $TMP/|1|1|w7|(none)" \
  "$(answer "$DOWN$BS$ENTER")"
# Neither of them touches anything from a row without a field.
check 'ctrl-backspace does nothing on a checkbox row' \
  "clone w1 -> w7 as-is|1|1|w7|(none)" \
  "$(answer "$DOWN$DOWN$BS$ENTER")"

# --- and completing it -------------------------------------------------------
# One match is filled in whole, so a typed prefix of the directory the popup
# offered confirms into it.
check 'tab completes a typed prefix' \
  "clone w1 -> w7 in $DIR/|1|1|w7|(none)" \
  "$(answer "$DOWN$CTRLU$TMP/re$TAB$ENTER")"
# Nothing matching invents nothing: what was typed stays as it was, which is not
# a directory, so the popup is still open and has decided nothing.
check 'a prefix that matches nothing completes to nothing' \
  "stdin closed for w7|(unset)|(unset)|(none)|(none)" \
  "$(answer "$DOWN$CTRLU$TMP/zz$TAB$ENTER")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
