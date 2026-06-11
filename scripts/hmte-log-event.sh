#!/usr/bin/env bash
# hmte-log-event.sh - Append event to run ledger
# Usage: hmte-log-event.sh <event_type> <json_data>

set -euo pipefail

# Determine .phase_control location
# Priority: 1) CWD/.phase_control 2) SKILL_DIR/../../../.phase_control (Hermes install)
if [ -d ".phase_control" ]; then
    CTRL=".phase_control"
elif [ -n "${HMTE_SKILL_DIR:-}" ] && [ -d "$HMTE_SKILL_DIR/../../../.phase_control" ]; then
    CTRL="$HMTE_SKILL_DIR/../../../.phase_control"
else
    echo "Error: .phase_control not found" >&2
    exit 1
fi

LEDGER="$CTRL/run_ledger.jsonl"

# Get arguments
EVENT_TYPE="${1:-unknown}"
if [ $# -ge 2 ]; then
    JSON_DATA="$2"
else
    JSON_DATA='{}'
fi

# Generate timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")

# Build event JSON with Python to avoid shell escaping issues
python3 - "$LEDGER" "$EVENT_TYPE" "$TIMESTAMP" "$JSON_DATA" <<'PY'
import json
import sys

ledger_path, event_type, timestamp, raw_data = sys.argv[1:5]

try:
    data = json.loads(raw_data) if raw_data else {}
except json.JSONDecodeError:
    data = {"raw": raw_data}

event = {
    "timestamp": timestamp,
    "event": event_type,
    "data": data,
}

with open(ledger_path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(event, ensure_ascii=False) + "\n")
PY
