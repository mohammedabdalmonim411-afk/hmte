#!/bin/bash
# Show Team Engine status

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

STATE_FILE=".phase_control/state.json"
LOCK_FILE=".phase_control/run.lock"
PHASES_FILE=".phase_control/phases.yaml"

echo "=== Mavis Team Engine Status ==="
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
    SESSION_ID=$(jq -r '.session_id' "$STATE_FILE")
    MODE=$(jq -r '.mode' "$STATE_FILE")
    CURRENT_PHASE=$(jq -r '.current_phase' "$STATE_FILE")
    PHASE_STATUS=$(jq -r '.phase_status' "$STATE_FILE")
    STARTED_AT=$(jq -r '.started_at' "$STATE_FILE")
    
    echo "Session ID: $SESSION_ID"
    echo "Mode: $MODE"
    echo "Started: $STARTED_AT"
    echo "Current Phase: $CURRENT_PHASE"
    echo "Phase Status: $PHASE_STATUS"
    echo ""
fi

# Show phases
if [ -f "$PHASES_FILE" ]; then
    PHASE_COUNT=$(yq eval '.phases | length' "$PHASES_FILE" 2>/dev/null || echo "0")
    echo "=== Phases ==="
    echo "Total phases: $PHASE_COUNT"
    
    if [ "$PHASE_COUNT" -gt 0 ]; then
        yq eval '.phases[] | "- " + .id + ": " + .name' "$PHASES_FILE" 2>/dev/null || echo "Unable to parse phases"
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
    VERDICT_COUNT=$(ls -1 "$VERDICTS_DIR"/*.txt 2>/dev/null | wc -l)
    echo "=== Verdicts ==="
    echo "Verdicts: $VERDICT_COUNT"
    if [ "$VERDICT_COUNT" -gt 0 ]; then
        for verdict_file in "$VERDICTS_DIR"/*.txt; do
            if [ -f "$verdict_file" ]; then
                VERDICT=$(head -n1 "$verdict_file" | grep -oP 'VERDICT: \K\w+' || echo "UNKNOWN")
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
