#!/usr/bin/env bash
# Counts total test assertions across every scenes/battle/*.tscn suite by parsing
# each suite's own printed summary line.
#
# Recognizes exactly three print formats used across this project's test suites
# (see CLAUDE.md's testing-conventions section — "manual assertion-total recounts
# must account for integration_test.tscn's different print format" — for the
# history of why this needs to be explicit rather than assumed):
#   1. "<suite_name>: N/M passed"                      (the majority of suites)
#   2. "=== Results: N passed, M failed ==="            (damage/move/stat/status_test)
#   3. "Integration tests: N passed, M failed"          (integration_test only)
#
# Usage:
#   scripts/count_assertions.sh                  # runs a fresh full sweep itself
#   scripts/count_assertions.sh path/to/log.txt  # parses an already-captured sweep log
#
# This script does NOT itself verify that the printed counts match the actual
# number of assertion calls in each suite's source — see the diagnostic session
# dated 2026-07-06 in docs/decisions.md for that independent cross-check. Re-run
# that cross-check whenever this script's patterns are changed.

set -euo pipefail

GODOT="/home/rob/Godot_v4.3-stable_linux.x86_64"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -ge 1 ]]; then
	LOG_FILE="$1"
else
	LOG_FILE="$(mktemp)"
	trap 'rm -f "$LOG_FILE"' EXIT
	cd "$PROJECT_DIR"
	for f in scenes/battle/*.tscn; do
		echo "=== $f ==="
		timeout 25 "$GODOT" --headless --path . "$f" 2>&1
	done > "$LOG_FILE"
fi

python3 - "$LOG_FILE" <<'PYEOF'
import re
import sys

log_file = sys.argv[1]
with open(log_file) as f:
	lines = f.readlines()

file_boundary = re.compile(r'^=== scenes/battle/.*\.tscn ===\s*$')
slash_re = re.compile(r'^(\w+):\s*(\d+)/(\d+)\s*passed\s*$')
results_re = re.compile(r'^=== Results:\s*(\d+)\s*passed,\s*(\d+)\s*failed\s*===\s*$')
integration_re = re.compile(r'^Integration tests:\s*(\d+)\s*passed,\s*(\d+)\s*failed\s*$')

files = []
current_file = None
current_lines = []
for line in lines:
	if file_boundary.match(line):
		if current_file is not None:
			files.append((current_file, current_lines))
		current_file = line.strip()
		current_lines = []
	else:
		current_lines.append(line)
if current_file is not None:
	files.append((current_file, current_lines))

grand_total = 0
no_match = []
print(f"{'FILE':50s} {'COUNT':>6s}  MATCHED LINE")
for fname, flines in files:
	count_for_file = 0
	matched_line = ""
	for line in flines:
		stripped = line.strip()
		m = slash_re.match(stripped)
		if m:
			count_for_file += int(m.group(2))
			matched_line = stripped
			continue
		m = results_re.match(stripped)
		if m:
			count_for_file += int(m.group(1))
			matched_line = stripped
			continue
		m = integration_re.match(stripped)
		if m:
			count_for_file += int(m.group(1))
			matched_line = stripped
			continue
	grand_total += count_for_file
	short_name = fname.replace("=== ", "").replace(" ===", "")
	if matched_line == "":
		no_match.append(short_name)
	print(f"{short_name:50s} {count_for_file:6d}  {matched_line}")

print()
print(f"Files detected: {len(files)}")
if no_match:
	print(f"Files with NO recognized summary line (expected only for battle_test.tscn, "
			f"the narrative-only M1 smoke test): {no_match}")
print(f"GRAND TOTAL: {grand_total}")
PYEOF
