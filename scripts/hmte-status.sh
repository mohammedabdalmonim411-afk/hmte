#!/bin/bash
# Show HTE status

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

STATE_FILE=".phase_control/state.json"
LOCK_FILE=".phase_control/run.lock"
PHASES_FILE=".phase_control/phases.json"

echo "=== HTE Status ==="
echo ""

# Check if running
if [ -f "$LOCK_FILE" ]; then
    echo "Status: RUNNING"
    echo "Lock PID: $(cat "$LOCK_FILE")"
else
    echo "Status: STOPPED"
fi

echo ""

# Show session info
if [ -f "$STATE_FILE" ]; then
    echo "=== Session Info ==="
    SESSION_ID=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('session_id', ''))" 2>/dev/null || echo "")
    MODE=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('mode', ''))" 2>/dev/null || echo "")
    CURRENT_PHASE=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('current_phase', ''))" 2>/dev/null || echo "")
    PHASE_STATUS=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('phase_status', ''))" 2>/dev/null || echo "")
    STARTED_AT=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('started_at', ''))" 2>/dev/null || echo "")
    
    echo "Session ID: $SESSION_ID"
    echo "Mode: $MODE"
    echo "Started: $STARTED_AT"
    echo "Current Phase: $CURRENT_PHASE"
    echo "Phase Status: $PHASE_STATUS"
    echo ""
fi

# Show phases
if [ -f "$PHASES_FILE" ]; then
    PHASE_COUNT=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(len(data.get('phases', [])))
except:
    print(0)
" "$PHASES_FILE" 2>/dev/null || echo "0")
    echo "=== Phases ==="
    echo "Total phases: $PHASE_COUNT"
    
    if [ "$PHASE_COUNT" -gt 0 ]; then
        python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for p in data.get('phases', []):
    print(f\"- {p.get('id', '?')}: {p.get('name', '?')}\")
" "$PHASES_FILE" 2>/dev/null || echo "Unable to parse phases"
    fi
    echo ""
fi

# Show evidence files
EVIDENCE_DIR=".phase_control/evidence"
if [ -d "$EVIDENCE_DIR" ]; then
    EVIDENCE_COUNT=$(ls -1 "$EVIDENCE_DIR"/*.json 2>/dev/null | wc -l)
    echo "=== Evidence ==="
    echo "Evidence bundles: $EVIDENCE_COUNT"
    if [ "$EVIDENCE_COUNT" -gt 0 ]; then
        ls -1 "$EVIDENCE_DIR"/*.json | xargs -n1 basename
    fi
    echo ""
fi

# Show verdicts
VERDICTS_DIR=".phase_control/verdicts"
if [ -d "$VERDICTS_DIR" ]; then
    VERDICT_COUNT=$(ls -1 "$VERDICTS_DIR"/*.json 2>/dev/null | wc -l)
    echo "=== Verdicts ==="
    echo "Verdicts: $VERDICT_COUNT"
    if [ "$VERDICT_COUNT" -gt 0 ]; then
        for verdict_file in "$VERDICTS_DIR"/*.json; do
            if [ -f "$verdict_file" ]; then
                VERDICT=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get('status', 'UNKNOWN'))
" "$verdict_file" 2>/dev/null || echo "UNKNOWN")
                echo "- $(basename "$verdict_file"): $VERDICT"
            fi
        done
    fi
    echo ""
fi

# Show background services
PIDS_DIR=".phase_control/pids"
if [ -d "$PIDS_DIR" ]; then
    echo "=== Background Services ==="
    RUNNING=0
    for pid_file in "$PIDS_DIR"/*.pid; do
        if [ -f "$pid_file" ]; then
            PID=$(cat "$pid_file")
            SERVICE=$(basename "$pid_file" .pid)
            if kill -0 "$PID" 2>/dev/null; then
                echo "- $SERVICE: RUNNING (PID: $PID)"
                RUNNING=$((RUNNING + 1))
            else
                echo "- $SERVICE: STOPPED (stale PID file)"
            fi
        fi
    done
    
    if [ "$RUNNING" -eq 0 ]; then
        echo "No running services"
    fi
fi
