#!/bin/bash
# Start HMTE session with atomic lock

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

STATE_FILE=".phase_control/state.json"
LOCK_FILE=".phase_control/run.lock"

echo "Starting HMTE..."

# Atomic lock creation using noclobber
set -C
if ! echo $$ > "$LOCK_FILE" 2>/dev/null; then
    set +C
    # Lock file exists, check if process is still running
    if [ -f "$LOCK_FILE" ]; then
        OLD_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            echo "ERROR: HMTE is already running (PID: $OLD_PID)"
            exit 1
        else
            echo "WARNING: Stale lock file found (PID $OLD_PID not running)"
            echo "Removing stale lock and continuing..."
            rm -f "$LOCK_FILE"
            # Try again with lock
            set -C
            if ! echo $$ > "$LOCK_FILE" 2>/dev/null; then
                set +C
                echo "ERROR: Failed to create lock file after removing stale lock"
                exit 1
            fi
            set +C
        fi
    else
        echo "ERROR: Failed to create lock file"
        exit 1
    fi
else
    set +C
fi

# Initialize state if needed
if [ ! -f "$STATE_FILE" ]; then
    NEEDS_INIT=1
else
    # Validate existing state file
    if ! python3 -c "import json; json.load(open('$STATE_FILE'))" 2>/dev/null; then
        echo "WARNING: Corrupted state file detected, backing up and reinitializing..."
        mv "$STATE_FILE" "${STATE_FILE}.corrupted.$(date +%s)"
        NEEDS_INIT=1
    else
        SESSION_ID=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('session_id', ''))" 2>/dev/null || echo "")
        if [ -z "$SESSION_ID" ]; then
            NEEDS_INIT=1
        else
            NEEDS_INIT=0
        fi
    fi
fi

if [ "$NEEDS_INIT" = "1" ]; then
    # Generate session ID
    if command -v uuidgen &> /dev/null; then
        SESSION_ID=$(uuidgen)
    else
        SESSION_ID="session_$(date +%s)_$$"
    fi
    
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    
    # Use Python to create initial state safely
    python3 << PYTHON_EOF
import json
state = {
    "session_id": "$SESSION_ID",
    "project_root": "$PROJECT_ROOT",
    "mode": "skill-only",
    "goal": "",
    "current_phase": "",
    "phase_status": "pending",
    "retries_used": 0,
    "max_retries": 2,
    "started_at": "$TIMESTAMP",
    "updated_at": "$TIMESTAMP",
    "active_worker": "",
    "active_verifier": "",
    "evidence_paths": [],
    "verdict_path": "",
    "next_action": ""
}
with open("$STATE_FILE", 'w') as f:
    json.dump(state, f, indent=2)
PYTHON_EOF
    
    echo "Initialized new session: $SESSION_ID"
fi

echo "HMTE started successfully"
echo "Project root: $PROJECT_ROOT"
echo "State file: $STATE_FILE"
echo "Lock file: $LOCK_FILE (PID: $$)"
echo ""
echo "To use HMTE, invoke the 'mavis-team-engine' skill in Hermes"
