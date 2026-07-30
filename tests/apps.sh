#!/usr/bin/env sh
# Unit tests for reopening what the panes were running — reading a command back
# out of a pane's process tree, pairing a rebuilt tab's panes with the ones they
# were cloned from, and typing the commands into the right ones.
#
#   ./tests/apps.sh
#
# `herdr` here is a stub script: it answers `pane process-info` from a table of
# fixtures and records every `pane run` it is asked to make, so the pairing can be
# checked without a herdr server, a terminal, or a real workspace.

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)

command -v jq >/dev/null 2>&1 || {
  echo "tests: jq not found on PATH" >&2
  exit 1
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/clone-layout-apps.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

HERDR_PLUGIN_STATE_DIR="$TMP/state"
export HERDR_PLUGIN_STATE_DIR
HERDR_CLONE_LAYOUT_LOG=0
export HERDR_CLONE_LAYOUT_LOG

# ---------------------------------------------------------------------------
# the stub herdr
#
# process-info answers from $TMP/proc/<pane>.json when there is one, and reports
# a pane sitting at its shell prompt when there isn't. `pane run` appends
# "<pane> <command>" to $TMP/ran, which is what the pairing tests read back.
# ---------------------------------------------------------------------------
mkdir -p "$TMP/proc"
cat >"$TMP/herdr" <<'STUB'
#!/usr/bin/env sh
case "$1 $2" in
  "pane process-info")
    pane=$4
    if [ -f "$PROC/$pane.json" ]; then
      cat "$PROC/$pane.json"
    else
      printf '{"result":{"process_info":{"pane_id":"%s","shell_pid":10,"foreground_process_group_id":10,"foreground_processes":[{"argv":["/bin/sh"],"cmdline":"/bin/sh","name":"sh","pid":10}]}}}\n' "$pane"
    fi
    ;;
  "pane run") printf '%s %s\n' "$3" "$4" >>"$RAN" ;;
  *) : ;;
esac
STUB
chmod +x "$TMP/herdr"
PROC="$TMP/proc"; export PROC
RAN="$TMP/ran";   export RAN
HERDR_BIN_PATH="$TMP/herdr"
export HERDR_BIN_PATH

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

# A pane's process table: the foreground process group as herdr reports it.
proc_fixture() { # pane shell_pid group_pid processes_json
  printf '{"result":{"process_info":{"pane_id":"%s","shell_pid":%s,"foreground_process_group_id":%s,"foreground_processes":%s}}}\n' \
    "$1" "$2" "$3" "$4" >"$PROC/$1.json"
}

# --- reading the command back out of a pane ----------------------------------
# A pane whose foreground process is its own shell is at a prompt: nothing to
# reopen. Anything else reports the group leader — the command that was started,
# not the children it went on to fork.
check 'a pane at its shell prompt has no command' '' "$(pane_command w1:p0)"

proc_fixture w1:p1 20135 414182 \
  '[{"cmdline":"nvim .","pid":414182,"cwd":"/repo"}]'
check 'a single foreground process is the command' 'nvim .' "$(pane_command w1:p1)"

proc_fixture w1:p2 20143 786268 \
  '[{"cmdline":"node /usr/bin/pnpm run dev","pid":786268},
    {"cmdline":"node /usr/bin/pnpm --filter web dev","pid":786292},
    {"cmdline":"next-server (v15)","pid":1235107}]'
check 'the group leader wins over its children' 'node /usr/bin/pnpm run dev' \
  "$(pane_command w1:p2)"

# Out-of-order children, and a leader that isn't first in the list.
proc_fixture w1:p3 20150 900 \
  '[{"cmdline":"child","pid":901},{"cmdline":"make watch","pid":900}]'
check 'the leader is found wherever it sits' 'make watch' "$(pane_command w1:p3)"

# No leader in the list at all (it exited between the two reads): fall back to
# the first non-shell process rather than reporting nothing.
proc_fixture w1:p4 20160 999 '[{"cmdline":"htop","pid":1001}]'
check 'a missing leader falls back to the first' 'htop' "$(pane_command w1:p4)"

# A command is typed into a shell, so control characters are stripped and the
# result trimmed — one command, on one line.
proc_fixture w1:p5 20170 500 \
  '[{"cmdline":"  tail -f log\tfile\n","pid":500}]'
check 'control characters never reach the shell' 'tail -f log file' \
  "$(pane_command w1:p5)"

proc_fixture w1:p6 20180 600 '[]'
check 'an empty process list has no command'  '' "$(pane_command w1:p6)"
check 'neither does a pane herdr cannot see' '' "$(pane_command w1:pZZ)"

# --- pairing panes up by position --------------------------------------------
# Two tabs with the same geometry list their panes in the same order, so position
# is all the pairing needs. The rects below are a 2x2 grid given in a deliberately
# jumbled order, to prove the sort and not the input.
GRID='{"layouts":[{"tab_id":"t1","panes":[
  {"pane_id":"bottom-right","rect":{"x":40,"y":20,"width":40,"height":20}},
  {"pane_id":"top-right",   "rect":{"x":40,"y":0, "width":40,"height":20}},
  {"pane_id":"bottom-left", "rect":{"x":0, "y":20,"width":40,"height":20}},
  {"pane_id":"top-left",    "rect":{"x":0, "y":0, "width":40,"height":20}}]}]}'
check 'panes come back top-to-bottom, left-to-right' \
  'top-left top-right bottom-left bottom-right' \
  "$(tab_pane_ids "$GRID" t1 | tr '\n' ' ' | sed 's/ $//')"
check 'a tab with no layout has no panes' '' "$(tab_pane_ids "$GRID" tZ)"

# The commands of a whole tab, in that same order, with an empty string standing
# in for a pane that was at its prompt — the positions have to keep lining up.
SRC='{"layouts":[{"tab_id":"s1","panes":[
  {"pane_id":"w1:p1","rect":{"x":0, "y":0,"width":40,"height":40}},
  {"pane_id":"w1:p0","rect":{"x":40,"y":0,"width":40,"height":40}},
  {"pane_id":"w1:p2","rect":{"x":80,"y":0,"width":40,"height":40}}]}]}'
check 'a tab reports one command per pane, in order' \
  '["nvim .","","node /usr/bin/pnpm run dev"]' "$(tab_commands "$SRC" s1)"
check 'a tab with no panes reports no commands' '[]' "$(tab_commands "$SRC" sZ)"

# --- typing them into the rebuilt tab ----------------------------------------
# run_commands reads the rebuilt tab out of a live snapshot, so that is what gets
# stood in for here.
NEW='{"layouts":[{"tab_id":"n1","panes":[
  {"pane_id":"w9:p1","rect":{"x":0, "y":0,"width":40,"height":40}},
  {"pane_id":"w9:p2","rect":{"x":40,"y":0,"width":40,"height":40}},
  {"pane_id":"w9:p3","rect":{"x":80,"y":0,"width":40,"height":40}}]}]}'
snapshot() { printf '%s' "$NEW"; }

ran() { # -> what the stub was asked to run, one pane per line
  rm -f "$RAN"
  run_commands "$@"
  cat "$RAN" 2>/dev/null | tr '\n' ';'
}

check 'each command lands on the pane in its position' \
  'w9:p1 nvim .;w9:p3 make watch;' \
  "$(ran n1 '["nvim .","","make watch"]')"
check 'a pane that was at a prompt is left alone' \
  'w9:p2 htop;' \
  "$(ran n1 '["","htop",""]')"
check 'nothing to reopen runs nothing' '' "$(ran n1 '["","",""]')"
check 'an empty command list runs nothing' '' "$(ran n1 '[]')"

# A tab that came out with a different number of panes has no trustworthy
# pairing left — typing a command into the wrong pane is worse than typing none.
check 'a pane count that does not match runs nothing' '' \
  "$(ran n1 '["nvim .","make watch"]')"
check 'and neither does an unknown tab' '' "$(ran nZ '["nvim ."]')"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
