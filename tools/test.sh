#!/usr/bin/env bash
# Runs everything CI runs. Usage: GODOT=/path/to/godot tools/test.sh
# Fails on any failed test or any SCRIPT ERROR in the output (GDScript runtime
# errors don't stop a test on their own, so we catch them here).
set -uo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
log=$(mktemp)
status=0

"$GODOT" --headless --path . --import >/dev/null 2>&1

echo "== unit tests"
"$GODOT" --headless --path . -s res://tests/run_tests.gd 2>&1 | tee -a "$log" | grep -E "PASS|FAIL|^\s+- |passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || status=1

echo "== scene smoke test"
"$GODOT" --headless --path . res://tests/smoke.tscn 2>&1 | tee -a "$log" | grep "\[smoke\]"
[ "${PIPESTATUS[0]}" -eq 0 ] || status=1

if grep -q "SCRIPT ERROR" "$log"; then
  echo "== SCRIPT ERRORS:"
  grep -A3 "SCRIPT ERROR" "$log"
  status=1
fi
rm -f "$log"
[ $status -eq 0 ] && echo "ALL GOOD" || echo "FAILED"
exit $status
