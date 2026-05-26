#!/bin/bash
# Stop Team Engine session

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

LOCK_FILE=".phase_control/run.lock"
PIDS_DIR=".phase_control/pids"

echo "Stopping Mavis Team Engine..."

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

echo "Team Engine stopped"
