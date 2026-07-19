#!/usr/bin/env bash
# ADR 12: launches every cell of the dynamic-vs-static allocation sweep as a
# separate headless Godot run with --log-metrics, writing one CSV per run to
# results/. External to the Godot project by design (ADR 12's "no engine
# dependency" choice) - this is just a loop over ExperimentCLI flags
# (simulation/experiment_cli.gd) that Tickets 01-03 already made every run
# accept.
#
# ADR 12 amendment (Ticket 07): each run's stderr is captured to a per-run
# <tag>.stderr.log under results/, rather than discarded - this is how the
# oscillation-backstop qualitative case gets detected (analyze.py greps for
# GoapCycle.gd's existing push_error message; a run that never trips it
# produces an empty log, which is itself the expected, citable result).
# Failure detection still keys off Godot's exit code only, never stderr
# content, so a run that legitimately logs nothing to stderr but exits
# nonzero is still caught.
#
# Usage: ./run_sweep.sh
# Env overrides: GODOT, FIXED_FPS, DURATION, SEEDS, POPULATIONS,
#                RESPAWN_TIMES, MODES (space-separated lists where relevant)
#
# Smoke-test example (4 runs, ~5 sim-seconds each):
#   POPULATIONS=8 RESPAWN_TIMES=30 SEEDS="1 2" DURATION=5 ./run_sweep.sh

set -uo pipefail  # no -e: a single failed cell must not abort the sweep

GODOT="${GODOT:-/c/Users/arthu/Downloads/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe}"
FIXED_FPS="${FIXED_FPS:-240}"
DURATION="${DURATION:-600}"
SEEDS="${SEEDS:-1 2 3 4 5}"
POPULATIONS="${POPULATIONS:-4 8 16}"
RESPAWN_TIMES="${RESPAWN_TIMES:-10 30 90}"
MODES="${MODES:-dynamic static}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
FAIL_LOG="$SCRIPT_DIR/failed_runs.log"

mkdir -p "$RESULTS_DIR"
: > "$FAIL_LOG"

total=0
failed=0

for pop in $POPULATIONS; do
	for respawn in $RESPAWN_TIMES; do
		for mode in $MODES; do
			for run_seed in $SEEDS; do
				total=$((total + 1))
				tag="pop${pop}_respawn${respawn}_${mode}_seed${run_seed}"
				echo "[$total] $tag"

				if ! "$GODOT" --headless --fixed-fps "$FIXED_FPS" --path "$REPO_ROOT" res://Main.tscn -- \
					--log-metrics --duration="$DURATION" \
					--agent-count="$pop" --respawn-time="$respawn" \
					--distribution-mode="$mode" --seed="$run_seed" \
					>/dev/null 2>"$RESULTS_DIR/${tag}.stderr.log"; then
					echo "  FAILED - see $FAIL_LOG"
					echo "$tag" >>"$FAIL_LOG"
					failed=$((failed + 1))
				fi
			done
		done
	done
done

echo ""
echo "Sweep complete: $total runs attempted, $failed failed."
if [ "$failed" -gt 0 ]; then
	echo "Failed cells recorded in $FAIL_LOG"
fi
