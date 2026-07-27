#!/usr/bin/env sh
# Offline tests for lib/plan.jq — the geometry analysis that turns a herdr
# snapshot into an ordered list of split steps. Pure jq: no herdr server, no
# terminal, nothing to clean up.
#
#   ./tests/run.sh            run every fixture
#   ./tests/run.sh grid       run fixtures whose filename matches "grid"
#
# Each fixture in tests/fixtures/ carries its own snapshot, the workspace to
# plan for, and the expected plan.

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
PLAN_JQ="$ROOT/lib/plan.jq"
FILTER=${1:-}

command -v jq >/dev/null 2>&1 || {
  echo "tests: jq not found on PATH" >&2
  exit 1
}

pass=0
fail=0

for f in "$ROOT"/tests/fixtures/*.json; do
  base=$(basename "$f" .json)
  case "$base" in
  *"$FILTER"*) ;;
  *) continue ;;
  esac

  name=$(jq -r '.name // ""' "$f")
  ws=$(jq -r '.ws' "$f")

  actual=$(jq -c --argjson snap "$(jq -c '.snapshot' "$f")" --arg ws "$ws" -f "$PLAN_JQ" -n 2>&1)
  status=$?
  expected=$(jq -c '.expected' "$f")

  if [ "$status" -ne 0 ]; then
    fail=$((fail + 1))
    printf 'FAIL %s — %s\n     jq error: %s\n' "$base" "$name" "$actual"
  elif [ "$actual" = "$expected" ]; then
    pass=$((pass + 1))
    printf 'ok   %s — %s\n' "$base" "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL %s — %s\n     expected: %s\n     actual:   %s\n' \
      "$base" "$name" "$expected" "$actual"
  fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
