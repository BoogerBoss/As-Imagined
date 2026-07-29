#!/usr/bin/env bash
# Run the overworld suite and treat ENGINE ERROR LINES AS FAILURES.
#
# Why this exists: a GDScript runtime error does not fail a suite by itself.
# It prints an ERROR line, aborts the function it happened in, and everything
# after it in that function silently never runs -- while the summary line still
# reports a cheerful N/N. A `%r` in an assertion label (Python syntax, not
# GDScript) did exactly that here, killing a test function on every run for
# several sessions. Only Z.99's arithmetic noticed, and only because it was
# there; a suite without that balance check would have shown green forever.
#
# So: any ERROR / SCRIPT ERROR line fails the run, as does a missing summary
# line, as does N != M. All three are silent-failure modes on their own.
#
# Absolute paths throughout -- see CLAUDE.md's working-directory rule.
set -uo pipefail

PROJECT="/home/rob/GodotAsImagined/as-imagined"
GODOT="${GODOT:-/home/rob/Godot_v4.7.1-stable_linux.x86_64}"
SCENE="${1:-scenes/overworld/m27a_step_resolver_test.tscn}"

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

# --autoplay is belt-and-braces; the suite's quit is unconditional now.
timeout 300 "$GODOT" --headless --path "$PROJECT" "$SCENE" --autoplay >"$LOG" 2>&1
RUN_RC=$?

cat "$LOG"
echo "----------------------------------------------------------------"

RC=0

if [ $RUN_RC -ne 0 ]; then
	echo "FAIL: godot exited $RUN_RC (124 == timed out, i.e. it never quit)"
	RC=1
fi

# Godot writes engine errors to stderr, already merged into $LOG above.
if grep -qE '^(ERROR|SCRIPT ERROR|USER ERROR):' "$LOG"; then
	echo "FAIL: engine ERROR lines present — a run with errors is not a pass:"
	grep -nE '^(ERROR|SCRIPT ERROR|USER ERROR):' "$LOG" | sed 's/^/    /'
	RC=1
fi

SUMMARY="$(grep -oE '[a-z0-9_]+: [0-9]+/[0-9]+ passed' "$LOG" | tail -1)"
if [ -z "$SUMMARY" ]; then
	echo "FAIL: no summary line — the suite did not reach its own report"
	RC=1
else
	PASSED="$(echo "$SUMMARY" | grep -oE '[0-9]+/' | tr -d /)"
	TOTAL="$(echo "$SUMMARY"  | grep -oE '/[0-9]+' | tr -d /)"
	if [ "$PASSED" != "$TOTAL" ]; then
		echo "FAIL: $SUMMARY"
		RC=1
	fi
fi

[ $RC -eq 0 ] && echo "PASS: $SUMMARY, no engine errors"
exit $RC
