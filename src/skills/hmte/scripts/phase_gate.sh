#!/bin/bash
# Phase gate - check if phase can proceed

set -e

PHASE_ID="$1"
STATE_FILE=".phase_control/state.json"
VERDICTS_DIR=".phase_control/verdicts"

if [ -z "$PHASE_ID" ]; then
    echo "Usage: phase_gate.sh <phase_id>"
    exit 1
fi

# Find latest verdict for this phase
LATEST_VERDICT=""
LATEST_ATTEMPT=0

for verdict_file in "$VERDICTS_DIR/${PHASE_ID}_attempt_"*.txt; do
    if [ -f "$verdict_file" ]; then
        ATTEMPT=$(echo "$verdict_file" | grep -oP 'attempt_\K\d+')
        if [ "$ATTEMPT" -gt "$LATEST_ATTEMPT" ]; then
            LATEST_ATTEMPT=$ATTEMPT
            LATEST_VERDICT="$verdict_file"
        fi
    fi
done

if [ -z "$LATEST_VERDICT" ]; then
    echo "BLOCKED: No verdict found for $PHASE_ID"
    exit 1
fi

# Check verdict
VERDICT=$(grep -oP 'VERDICT: \K\w+' "$LATEST_VERDICT")

if [ "$VERDICT" = "PASS" ]; then
    echo "PASS: Phase $PHASE_ID can proceed"
    exit 0
elif [ "$VERDICT" = "FAIL" ]; then
    echo "BLOCKED: Phase $PHASE_ID failed verification"
    exit 1
elif [ "$VERDICT" = "BLOCK" ]; then
    echo "BLOCKED: Phase $PHASE_ID is blocked"
    exit 1
else
    echo "BLOCKED: Unknown verdict: $VERDICT"
    exit 1
fi
