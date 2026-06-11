#!/bin/bash
# Show TAF legacy hmte status

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

STATE_FILE=".phase_control/state.json"
LOCK_FILE=".phase_control/run.lock"
PHASES_FILE=".phase_control/phases.json"

echo "=== TAF Legacy hmte Status ==="
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
    echo ""
fi

# Show run ledger
LEDGER_FILE=".phase_control/run_ledger.jsonl"
if [ -f "$LEDGER_FILE" ]; then
    echo "=== Run Ledger (last 10 events) ==="
    tail -n 10 "$LEDGER_FILE" | while IFS= read -r line; do
        if [ -n "$line" ]; then
            EVENT=$(echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin); data=d.get('data', {}) if isinstance(d.get('data', {}), dict) else {}; event=d.get('event', data.get('event', '')); phase=data.get('phase_id', d.get('phase_id', '')); verdict=data.get('verdict', d.get('verdict', '')); passed=data.get('passed', d.get('passed', '')); worker=data.get('worker_id', d.get('worker_id', '')); shard_info=f' worker={worker}' if worker else ''; print(f\"{d.get('timestamp','')} [{event}] phase={phase}{shard_info} verdict={verdict} passed={passed}\")" 2>/dev/null || echo "$line")
            echo "  $EVENT"
        fi
    done
    echo ""

    # v1.7: Show parallel shard progress
    PARALLEL_EVENTS=$(grep -c 'worker_shard_evidence_ready\|parallel_phase_started\|join_verification' "$LEDGER_FILE" 2>/dev/null || echo "0")
    if [ "$PARALLEL_EVENTS" -gt 0 ]; then
        echo "=== Parallel Shard Progress ==="
        python3 -c "
import json, sys
from collections import defaultdict

events = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if line:
            try:
                events.append(json.loads(line))
            except:
                pass

# Count shard evidence per phase
shard_counts = defaultdict(lambda: {'total': 0, 'ready': 0, 'workers': set()})
for e in events:
    data = e.get('data', {}) if isinstance(e.get('data', {}), dict) else {}
    event = e.get('event', data.get('event', ''))
    phase_id = data.get('phase_id', e.get('phase_id', ''))
    worker_id = data.get('worker_id', e.get('worker_id', ''))
    if event == 'parallel_phase_started':
        shard_counts[phase_id]['total'] = data.get('worker_count', 0)
    elif event == 'worker_shard_evidence_ready':
        shard_counts[phase_id]['ready'] += 1
        if worker_id:
            shard_counts[phase_id]['workers'].add(worker_id)

for pid, info in sorted(shard_counts.items()):
    workers = ', '.join(sorted(info['workers'])) if info['workers'] else 'unknown'
    total = info['total'] if info['total'] > 0 else '?'
    ready = info.get("ready", 0)
    print(f"  {pid}: {ready}/{total} shards ready -- workers: {workers}")
" "$LEDGER_FILE" 2>/dev/null || true
        echo ""
    fi
fi
