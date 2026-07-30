#!/usr/bin/env sh
# End-to-end tests for the dialog's key handling — the popup driven the way a
# keyboard drives it, with the keys arriving on stdin instead of from a terminal
# and a stub herdr standing in for a session. Each case checks the three things
# an answer decides: whether a layout is cloned, where its panes open, and what
# is remembered for the next new workspace.
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

# A herdr that answers `api snapshot` with an empty session and ignores the rest.
# The dialog logs which answer it took before it starts building, so an empty
# snapshot is enough to test the decisions without simulating a whole session.
cat >"$TMP/herdr" <<'STUB'
#!/usr/bin/env sh
case "$*" in
  "api snapshot") printf '{"result":{"snapshot":{"tabs":[],"panes":[],"workspaces":[],"layouts":[]}}}\n' ;;
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

# Types the keys into a fresh popup and reports what it decided, as
# "<log>|<clone box>|<apps box>|<workspaces recorded as done>". The two optional
# arguments seed the boxes, standing in for a popup answered earlier.
answer() { # keys [stored_clone_box] [stored_apps_box]
  state=$TMP/state
  rm -rf "$state"
  mkdir -p "$state"
  [ -n "${2:-}" ] && printf '%s\n' "$2" >"$state/clone-enabled"
  [ -n "${3:-}" ] && printf '%s\n' "$3" >"$state/reopen-apps"
  printf '%s' "$1" >"$TMP/keys"

  HERDR_PLUGIN_STATE_DIR=$state \
  HERDR_PLUGIN_ROOT=$ROOT \
  HERDR_BIN_PATH=$TMP/herdr \
  CLONE_LAYOUT_TARGET=w7 \
  CLONE_LAYOUT_FROM=w1 \
  CLONE_LAYOUT_DIR=$DIR \
    sh "$DIALOG" <"$TMP/keys" >/dev/null 2>&1

  printf '%s|%s|%s|%s' \
    "$(sed -n 's/^[0-9:]* dialog: //p' "$state/clone-layout.log" 2>/dev/null | head -n 1)" \
    "$(cat "$state/clone-enabled" 2>/dev/null || echo '(unset)')" \
    "$(cat "$state/reopen-apps" 2>/dev/null || echo '(unset)')" \
    "$(cat "$state/populated-workspaces" 2>/dev/null || echo '(none)')"
}

# --- the two directory answers, with both boxes left ticked ------------------
check 'enter clones as-is, as it always has' \
  "clone w1 -> w7 as-is|1|1|w7"      "$(answer "$ENTER")"
check 'the directory row clones into it' \
  "clone w1 -> w7 in $DIR|1|1|w7"    "$(answer "$DOWN$ENTER")"
check 'confirming on a box clones as-is' \
  "clone w1 -> w7 as-is|1|1|w7"      "$(answer "$DOWN$DOWN$ENTER")"
check 'tab wraps past both boxes to the top' \
  "clone w1 -> w7 as-is|1|1|w7"      "$(answer "$TAB$TAB$TAB$TAB$ENTER")"

# --- unticking the first box, then confirming above it -----------------------
# The boxes are rows of their own, so the flow is: down to one, space, back up to
# one of the two directory answers, enter. Whichever of the two you come back to,
# an unticked first box means nothing is cloned.
check 'unticked, confirmed from the top row' \
  "clone off, leaving w7 as it is|0|1|w7" "$(answer "$DOWN$DOWN$SPACE$UP$UP$ENTER")"
check 'unticked, confirmed from the directory row' \
  "clone off, leaving w7 as it is|0|1|w7" "$(answer "$DOWN$DOWN$SPACE$UP$ENTER")"
check 'ticking it back on clones again' \
  "clone w1 -> w7 as-is|1|1|w7"      "$(answer "$DOWN$DOWN$SPACE$SPACE$UP$UP$ENTER")"

# --- the second box, one row further down ------------------------------------
# It doesn't change what Enter does, only what the clone copies, so the log line
# is the same either way and the remembered answer is what moves.
check 'unticking the apps box still clones' \
  "clone w1 -> w7 as-is|1|0|w7"      "$(answer "$DOWN$DOWN$DOWN$SPACE$ENTER")"
check 'a stored no opens the apps box unticked' \
  "clone w1 -> w7 as-is|1|0|w7"      "$(answer "$ENTER" '' 0)"
check 'and space on it ticks it back on' \
  "clone w1 -> w7 as-is|1|1|w7"      "$(answer "$DOWN$DOWN$DOWN$SPACE$ENTER" '' 0)"
check 'both boxes are written by one enter' \
  "clone off, leaving w7 as it is|0|0|w7" \
  "$(answer "$DOWN$DOWN$SPACE$DOWN$SPACE$ENTER")"

# --- what the boxes remember -------------------------------------------------
check 'a stored no opens the popup unticked' \
  "clone off, leaving w7 as it is|0|1|w7" "$(answer "$ENTER" 0)"
check 'and space on the box undoes it' \
  "clone w1 -> w7 as-is|1|1|w7"      "$(answer "$DOWN$DOWN$SPACE$ENTER" 0)"

# --- esc decides nothing, including about the boxes --------------------------
check 'esc after unticking leaves both as they were' \
  "cancelled for w7|(unset)|(unset)|(none)" \
  "$(answer "$DOWN$DOWN$SPACE$DOWN$SPACE$ESC")"

# --- space belongs to the row it is standing on ------------------------------
# The top row has two boxes below it and no way to say which one is meant, so
# space does nothing there rather than guessing.
check 'space on the top row changes nothing' \
  "clone w1 -> w7 as-is|1|1|w7"      "$(answer "$SPACE$ENTER")"
# On the directory row a space is a character, so it lands in the path and the
# popup stays open on a directory that isn't there — deciding nothing.
check 'space on the directory row types a space' \
  "stdin closed for w7|(unset)|(unset)|(none)" "$(answer "$DOWN$SPACE$ENTER")"

# --- a directory that isn't there is not an answer ---------------------------
check 'a bad path keeps the popup open' \
  "stdin closed for w7|(unset)|(unset)|(none)" "$(answer "${DOWN}/nowhere/at/all$ENTER")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
