#!/bin/bash
# Stop TAF legacy hmte session

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

SKILL_DIR="${HMTE_SKILL_DIR:-$PROJECT_ROOT/src/skills/hmte}"

# Call stop_gate to check if safe to stop
if [[ -x "$SKILL_DIR/hooks/stop_gate.sh" ]]; then
    bash "$SKILL_DIR/hooks/stop_gate.sh" || {
        echo "❌ stop_gate阻止了停止操作" >&2
        exit 1
    }
fi

LOCK_FILE=".phase_control/run.lock"
PIDS_DIR=".phase_control/pids"

echo "Stopping TAF legacy hmte runtime..."

# Stop all background services
if [ -d "$PIDS_DIR" ]; then
    for pid_file in "$PIDS_DIR"/*.pid; do
        if [ -f "$pid_file" ]; then
            PID=$(cat "$pid_file")
            SERVICE=$(basename "$pid_file" .pid)
            
            if kill -0 "$PID" 2>/dev/null; then
                echo "Stopping $SERVICE (PID: $PID)..."
                kill "$PID" 2>/dev/null || true
                sleep 1
                
                # Force kill if still running
                if kill -0 "$PID" 2>/dev/null; then
                    echo "Force stopping $SERVICE..."
                    kill -9 "$PID" 2>/dev/null || true
                fi
            fi
            
            rm -f "$pid_file"
        fi
    done
fi

# Remove lock file
if [ -f "$LOCK_FILE" ]; then
    rm -f "$LOCK_FILE"
    echo "Lock file removed"
fi

echo "TAF legacy hmte runtime stopped successfully"
echo ""
echo "To restart, run: ./scripts/hmte-start.sh"
echo "Then invoke the 'hmte' skill in Hermes"
