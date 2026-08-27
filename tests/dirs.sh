#!/usr/bin/env sh
# Tests for carrying pane directories across to a new checkout — measuring a
# pane's directory against the checkout it belonged to, reading it off the new
# one, and handing each pane of a clone the directory it should open in.
#
#   ./tests/dirs.sh
#
# The directories here are real: whether a path exists is half of what the code
# decides on, so they are made under a temp root rather than mocked. `herdr` is a
# stub script that keeps a session in a file — it appends the tabs and panes it
# is asked to create, so create-then-look-for-the-new-id works as it does against
# a server, and records the directory every one of them was opened in.

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)

command -v jq >/dev/null 2>&1 || {
  echo "tests: jq not found on PATH" >&2
  exit 1
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/clone-layout-dirs.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM
# The temp root itself may be reached through a symlink (/tmp is one on macOS).
# These tests compare paths the code has resolved, so start from a resolved one.
TMP=$(CDPATH='' cd -P -- "$TMP" && pwd -P)

HERDR_PLUGIN_STATE_DIR="$TMP/state"
export HERDR_PLUGIN_STATE_DIR
HERDR_CLONE_LAYOUT_LOG=0
export HERDR_CLONE_LAYOUT_LOG

# --- the tree on disk --------------------------------------------------------
# A main checkout, and a linked worktree of it that is missing one of the
# directories the checkout has — an ignored build directory, or one that only
# exists on the branch it was cloned from.
MAIN="$TMP/main"
WT="$TMP/wt/feature"
mkdir -p "$MAIN/src/components" "$MAIN/product/dashboard" "$MAIN/deep/a/b/c"
mkdir -p "$WT/src/components" "$WT/product" "$WT/deep"
mkdir -p "$TMP/notes" "$TMP/other-repo/lib"
# A second name for the main checkout, to prove a pane that reached it through a
# symlink is still recognised as being inside it.
ln -s "$MAIN" "$TMP/main-link"

# --- the stub herdr ---------------------------------------------------------
SESSION="$TMP/session.json"; export SESSION
REC="$TMP/recorded";         export REC
IDS="$TMP/ids";              export IDS

cat >"$TMP/herdr" <<'STUB'
#!/usr/bin/env sh
set -u
sess() { cat "$SESSION"; }
save() { printf '%s\n' "$1" >"$SESSION.tmp" && mv "$SESSION.tmp" "$SESSION"; }
# Ids of their own, so a stub-made tab never collides with one in the fixture.
next_id() {
  n=$(cat "$IDS" 2>/dev/null || echo 0)
  n=$((n + 1))
  echo "$n" >"$IDS"
  printf 'n%s' "$n"
}

case "${1:-} ${2:-}" in
  "tab create")
    shift 2
    ws=''; label=''; cwd=''
    while [ $# -gt 0 ]; do
      case $1 in
        --workspace) ws=$2; shift 2 ;;
        --label) label=$2; shift 2 ;;
        --cwd) cwd=$2; shift 2 ;;
        *) shift ;;
      esac
    done
    printf 'tab-create|%s|%s\n' "$label" "$cwd" >>"$REC"
    t="t$(next_id)"; p="p$(next_id)"
    save "$(sess | jq -c --arg w "$ws" --arg t "$t" --arg p "$p" --arg l "$label" --arg c "$cwd" '
      .tabs += [{tab_id: $t, workspace_id: $w, label: $l}]
      | .panes += [{pane_id: $p, workspace_id: $w, tab_id: $t, cwd: $c}]')"
    ;;
  "pane split")
    parent=$3
    shift 3
    dir=''; cwd=''
    while [ $# -gt 0 ]; do
      case $1 in
        --direction) dir=$2; shift 2 ;;
        --ratio) shift 2 ;;
        --cwd) cwd=$2; shift 2 ;;
        *) shift ;;
      esac
    done
    printf 'split|%s|%s|%s\n' "$parent" "$dir" "$cwd" >>"$REC"
    p="p$(next_id)"
    save "$(sess | jq -c --arg parent "$parent" --arg p "$p" --arg c "$cwd" '
      first(.panes[] | select(.pane_id == $parent)) as $pp
      | .panes += [{pane_id: $p, workspace_id: $pp.workspace_id, tab_id: $pp.tab_id, cwd: $c}]')"
    ;;
  "tab rename") printf 'rename|%s|%s\n' "$3" "$4" >>"$REC" ;;
  "tab close")
    printf 'close|%s\n' "$3" >>"$REC"
    save "$(sess | jq -c --arg t "$3" '
      .tabs |= map(select(.tab_id != $t)) | .panes |= map(select(.tab_id != $t))')"
    ;;
  "tab focus") printf 'focus|%s\n' "$3" >>"$REC" ;;
  *) : ;;
esac
STUB
chmod +x "$TMP/herdr"
HERDR_BIN_PATH="$TMP/herdr"
export HERDR_BIN_PATH

CLONE_LAYOUT_SOURCE=1
export CLONE_LAYOUT_SOURCE
# Path is only known at runtime, and CI lints bin/clone-layout directly anyway.
# shellcheck disable=SC1091
. "$ROOT/bin/clone-layout"
unset CLONE_LAYOUT_SOURCE

# The session lives in a file the stub appends to, not behind a socket.
snapshot() { cat "$SESSION"; }

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

# --- trailing slashes, and the paths that are only a slash -------------------
check 'a trailing slash comes off'      '/a/b' "$(strip_slash /a/b/)"
check 'so do several'                   '/a/b' "$(strip_slash /a/b///)"
check 'a path without one is untouched' '/a/b' "$(strip_slash /a/b)"
check 'root stays root'                 '/'    "$(strip_slash /)"
check 'and root with extras is root'    '/'    "$(strip_slash ///)"
check 'nothing in, nothing out'         ''     "$(strip_slash '')"

# --- is this directory inside that one? -------------------------------------
check 'a directory inside reports the path between' \
  'src/components' "$(rel_under "$MAIN/src/components" "$MAIN")"
check 'the checkout itself reports "."' '.' "$(rel_under "$MAIN" "$MAIN")"
check 'a trailing slash changes nothing' \
  'src/components' "$(rel_under "$MAIN/src/components/" "$MAIN/")"
check 'a sibling directory is not inside' '' "$(rel_under "$TMP/other-repo/lib" "$MAIN")"
# The prefix matches as a string but not as a path: main-elsewhere is not in main.
mkdir -p "$TMP/main-elsewhere/src"
check 'a name that merely starts the same is not inside' \
  '' "$(rel_under "$TMP/main-elsewhere/src" "$MAIN")"
check 'a symlinked route in is still inside' \
  'src/components' "$(rel_under "$TMP/main-link/src/components" "$MAIN")"
check 'and so is a symlinked base' \
  'src/components' "$(rel_under "$MAIN/src/components" "$TMP/main-link")"
# Neither directory has to still be there: a pane can report a cwd that has since
# been removed, and the names alone answer the question.
check 'directories that are gone are still measured' \
  'src/gone' "$(rel_under "$TMP/ghost/src/gone" "$TMP/ghost")"
check 'nothing to measure against' '' "$(rel_under "$MAIN/src" '')"
check 'nothing to measure'         '' "$(rel_under '' "$MAIN")"

# --- the deepest directory that is actually there ---------------------------
check 'a directory that exists is the answer' \
  "$WT/src/components" "$(nearest_dir "$WT/src/components" "$WT")"
check 'a missing leaf falls back to its parent' \
  "$WT/product" "$(nearest_dir "$WT/product/dashboard" "$WT")"
check 'several missing levels fall back to the deepest that is there' \
  "$WT/deep" "$(nearest_dir "$WT/deep/a/b/c" "$WT")"
check 'nothing under the floor exists, so the floor it is' \
  "$WT" "$(nearest_dir "$WT/nope/nope" "$WT")"
check 'the floor is never climbed past' \
  "$WT" "$(nearest_dir "$TMP/somewhere/else" "$WT")"

# --- where a cloned pane opens ----------------------------------------------
check 'a pane in the checkout root opens in the new checkout root' \
  "$WT" "$(remap_dir "$MAIN" "$MAIN" "$WT")"
check 'a pane in a subdirectory opens in the same subdirectory' \
  "$WT/src/components" "$(remap_dir "$MAIN/src/components" "$MAIN" "$WT")"
check 'a subdirectory the new checkout lacks opens as deep as it can' \
  "$WT/product" "$(remap_dir "$MAIN/product/dashboard" "$MAIN" "$WT")"
check 'a pane outside the checkout keeps the directory it had' \
  "$TMP/notes" "$(remap_dir "$TMP/notes" "$MAIN" "$WT")"
check 'a pane in another repository keeps it too' \
  "$TMP/other-repo/lib" "$(remap_dir "$TMP/other-repo/lib" "$MAIN" "$WT")"
check 'a pane that came in through a symlink still crosses over' \
  "$WT/src/components" "$(remap_dir "$TMP/main-link/src/components" "$MAIN" "$WT")"
# Directories with spaces in them are ordinary directories.
mkdir -p "$MAIN/a dir/b" "$WT/a dir/b"
check 'a space in the path is just a character' \
  "$WT/a dir/b" "$(remap_dir "$MAIN/a dir/b" "$MAIN" "$WT")"

# --- which two checkouts a clone is measured between ------------------------
# Only a new linked worktree gets this treatment, and only from a workspace in
# the same repository.
roots() { # source_worktree_json target_worktree_json
  snap=$(jq -n --argjson s "$1" --argjson t "$2" '
    {workspaces: [{workspace_id: "w1", worktree: $s}, {workspace_id: "w9", worktree: $t}]}')
  remap_roots "$snap" w1 w9 | tr '\n' ' ' | sed 's/ $//'
}
LINKED=$(jq -n --arg c "$WT" --arg r "$MAIN" \
  '{checkout_path: $c, repo_root: $r, is_linked_worktree: true}')
CHECKOUT=$(jq -n --arg c "$MAIN" --arg r "$MAIN" \
  '{checkout_path: $c, repo_root: $r, is_linked_worktree: false}')
OTHER=$(jq -n --arg c "$TMP/other-repo" --arg r "$TMP/other-repo" \
  '{checkout_path: $c, repo_root: $r, is_linked_worktree: false}')
SIBLING=$(jq -n --arg c "$TMP/wt/other" --arg r "$MAIN" \
  '{checkout_path: $c, repo_root: $r, is_linked_worktree: true}')

check 'a worktree made from the main checkout is measured against it' \
  "$MAIN $WT" "$(roots "$CHECKOUT" "$LINKED")"
check 'a worktree made from another worktree is measured against that one' \
  "$TMP/wt/other $WT" "$(roots "$SIBLING" "$LINKED")"
check 'a workspace herdr tracks no checkout for falls back to the main checkout' \
  "$MAIN $WT" "$(roots null "$LINKED")"
check 'a workspace in a different repository is left alone' \
  '' "$(roots "$OTHER" "$LINKED")"
check 'a plain new workspace is left alone' \
  '' "$(roots "$CHECKOUT" null)"
check 'so is a new main checkout — nothing to carry across' \
  '' "$(roots "$CHECKOUT" "$CHECKOUT")"
check 'a worktree with no path on record is left alone' \
  '' "$(roots "$CHECKOUT" "$(jq -n --arg r "$MAIN" '{repo_root: $r, is_linked_worktree: true}')")"

# --- the clone itself -------------------------------------------------------
# A source workspace with four panes across three tabs: one in a subdirectory the
# worktree has, one at the checkout root, one in a subdirectory it lacks, and one
# outside the checkout altogether.
session() { # source_worktree_json target_worktree_json
  rm -f "$REC" "$IDS"
  jq -n --argjson src "$1" --argjson tgt "$2" \
        --arg main "$MAIN" --arg wt "$WT" --arg notes "$TMP/notes" '
  {
    focused_workspace_id: "w1",
    workspaces: [
      {workspace_id: "w1", tab_count: 3, pane_count: 4, worktree: $src},
      {workspace_id: "w9", tab_count: 1, pane_count: 1, worktree: $tgt}
    ],
    tabs: [
      {tab_id: "w1:t1", workspace_id: "w1", label: "agent"},
      {tab_id: "w1:t2", workspace_id: "w1", label: "server"},
      {tab_id: "w1:t3", workspace_id: "w1", label: "notes"},
      {tab_id: "w9:t1", workspace_id: "w9", label: ""}
    ],
    panes: [
      {pane_id: "w1:p1", workspace_id: "w1", tab_id: "w1:t1", cwd: ($main + "/src/components")},
      {pane_id: "w1:p2", workspace_id: "w1", tab_id: "w1:t1", cwd: $main},
      {pane_id: "w1:p3", workspace_id: "w1", tab_id: "w1:t2", cwd: ($main + "/product/dashboard")},
      {pane_id: "w1:p4", workspace_id: "w1", tab_id: "w1:t3", cwd: $notes},
      {pane_id: "w9:p1", workspace_id: "w9", tab_id: "w9:t1", cwd: $wt}
    ],
    layouts: [
      {tab_id: "w1:t1", workspace_id: "w1",
       panes: [{pane_id: "w1:p1", rect: {x: 0, y: 0, width: 100, height: 60}},
               {pane_id: "w1:p2", rect: {x: 100, y: 0, width: 100, height: 60}}],
       splits: [{direction: "right", ratio: 0.5, rect: {x: 0, y: 0, width: 200, height: 60}}]},
      {tab_id: "w1:t2", workspace_id: "w1",
       panes: [{pane_id: "w1:p3", rect: {x: 0, y: 0, width: 200, height: 60}}], splits: []},
      {tab_id: "w1:t3", workspace_id: "w1",
       panes: [{pane_id: "w1:p4", rect: {x: 0, y: 0, width: 200, height: 60}}], splits: []},
      {tab_id: "w9:t1", workspace_id: "w9",
       panes: [{pane_id: "w9:p1", rect: {x: 0, y: 0, width: 200, height: 60}}], splits: []}
    ]
  }' >"$SESSION"
}

# What the clone asked herdr for, with the temp root and the stub's own pane ids
# folded away — the directories are what these tests are about.
built() { # [chosen_dir]
  do_clone "$(cat "$SESSION")" w1 w9 "${1:-}"
  [ -f "$REC" ] || return 0
  sed -e "s#$TMP#T#g" -e 's#|pn[0-9]*|#|NEW|#' "$REC" | tr '\n' ' ' | sed 's/ $//'
}

# Geometry only, so the reopen-apps path stays out of these expectations.
remember "$APPS_BOX" 0

# A new worktree: every pane opens in the matching directory of the new checkout.
# The first pane belongs in src/components rather than at the top of the
# worktree, so the workspace's own tab cannot stand in for it — every tab is
# built fresh and that one is closed.
session "$CHECKOUT" "$LINKED"
check 'a worktree gets each pane in its own directory under the new checkout' \
  'tab-create|agent|T/wt/feature/src/components split|NEW|right|T/wt/feature tab-create|server|T/wt/feature/product tab-create|notes|T/notes close|w9:t1' \
  "$(built)"

# The same, with the first pane at the checkout root: that IS where the
# workspace's own tab is already sitting, so it is reused and renamed, and
# nothing is closed.
session "$CHECKOUT" "$LINKED"
jq -c '(.panes[] | select(.pane_id == "w1:p1") | .cwd) |= "'"$MAIN"'"' "$SESSION" >"$SESSION.x" \
  && mv "$SESSION.x" "$SESSION"
check 'a first pane already in the right place reuses the tab that is there' \
  'rename|w9:t1|agent split|w9:p1|right|T/wt/feature tab-create|server|T/wt/feature/product tab-create|notes|T/notes' \
  "$(built)"

# A plain new workspace is not a second checkout of anything: no directories are
# carried across, and the panes inherit as they always did.
session "$CHECKOUT" null
check 'a plain new workspace hands out no directories at all' \
  'rename|w9:t1|agent split|w9:p1|right| tab-create|server| tab-create|notes|' \
  "$(built)"

# A directory chosen in the popup is an answer in its own right: every pane goes
# there, subdirectories and all.
session "$CHECKOUT" "$LINKED"
check 'a chosen directory puts every pane in it' \
  "tab-create|agent|T/notes split|NEW|right|T/notes tab-create|server|T/notes tab-create|notes|T/notes close|w9:t1" \
  "$(built "$TMP/notes")"

# A worktree whose directory has been removed from under it: there is nothing to
# open panes in, so the clone falls back to letting them inherit rather than
# handing herdr a directory that isn't there.
session "$CHECKOUT" "$(jq -n --arg c "$TMP/wt/gone" --arg r "$MAIN" \
  '{checkout_path: $c, repo_root: $r, is_linked_worktree: true}')"
check 'a checkout that is not on disk hands out no directories' \
  'rename|w9:t1|agent split|w9:p1|right| tab-create|server| tab-create|notes|' \
  "$(built)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
