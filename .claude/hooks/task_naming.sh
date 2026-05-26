#!/bin/bash
# Task naming hook
# Ensures task names align with phase IDs

TASK_SUBJECT="$1"
STATE_FILE=".phase_control/state.json"

# If no active phase, allow any name
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

CURRENT_PHASE=$(jq -r '.current_phase' "$STATE_FILE" 2>/dev/null || echo "")

# If no current phase, allow any name
if [ -z "$CURRENT_PHASE" ] || [ "$CURRENT_PHASE" = "null" ]; then
    exit 0
fi

# Check if task subject contains phase ID
if ! echo "$TASK_SUBJECT" | grep -qi "$CURRENT_PHASE"; then
    echo "WARNING: Task subject should reference current phase: $CURRENT_PHASE"
    echo "Task subject: $TASK_SUBJECT"
    # Don't block, just warn
fi

exit 0
