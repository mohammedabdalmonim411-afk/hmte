#!/bin/bash
# Stop gate hook
# Prevents stopping when work is incomplete

set -e

STATE_FILE=".phase_control/state.json"
PIDS_DIR=".phase_control/pids"

# Check if state file exists
if [ ! -f "$STATE_FILE" ]; then
    echo "No active Team Engine session"
    exit 0
fi

# Read current phase status
PHASE_STATUS=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('phase_status', ''))" 2>/dev/null || echo "")

# Check if phase is incomplete
if [ "$PHASE_STATUS" != "passed" ] && [ "$PHASE_STATUS" != "completed" ] && [ -n "$PHASE_STATUS" ]; then
    CURRENT_PHASE=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('current_phase', 'unknown'))" 2>/dev/null || echo "unknown")
    echo "BLOCKED: Phase $CURRENT_PHASE is not complete (status: $PHASE_STATUS)"
    echo "Please complete the current phase or explicitly abort."
    exit 1
fi

# Check for running background processes
if [ -d "$PIDS_DIR" ]; then
    for pid_file in "$PIDS_DIR"/*.pid; do
        if [ -f "$pid_file" ]; then
            PID=$(cat "$pid_file")
            if kill -0 "$PID" 2>/dev/null; then
                SERVICE=$(basename "$pid_file" .pid)
                echo "BLOCKED: Background service still running: $SERVICE (PID: $PID)"
                echo "Please stop the service first."
                exit 1
            fi
        fi
    done
fi

# Check for pending verdicts
EVIDENCE_DIR=".phase_control/evidence"
VERDICTS_DIR=".phase_control/verdicts"

if [ -d "$EVIDENCE_DIR" ]; then
    for evidence_file in "$EVIDENCE_DIR"/*.json; do
        if [ -f "$evidence_file" ]; then
            BASENAME=$(basename "$evidence_file" .json)
            VERDICT_FILE="$VERDICTS_DIR/${BASENAME}.json"
            if [ ! -f "$VERDICT_FILE" ]; then
                echo "BLOCKED: Evidence without verdict: $evidence_file"
                echo "Please complete verification or explicitly abort."
                exit 1
            fi
        fi
    done
fi

# Check verdict content - must be PASS
for verdict_file in "$VERDICTS_DIR"/*.json; do
    if [ -f "$verdict_file" ]; then
        VERDICT_STATUS=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(d.get('status', 'UNKNOWN'))
except:
    print('INVALID')
" "$verdict_file" 2>/dev/null || echo "INVALID")
        if [ "$VERDICT_STATUS" != "PASS" ]; then
            BASENAME=$(basename "$verdict_file" .json)
            echo "BLOCKED: Verdict $BASENAME has status $VERDICT_STATUS (not PASS)"
            echo "Please complete verification with PASS verdict."
            exit 1
        fi
    fi
done

# All checks passed
echo "All phases complete, safe to stop."
exit 0
